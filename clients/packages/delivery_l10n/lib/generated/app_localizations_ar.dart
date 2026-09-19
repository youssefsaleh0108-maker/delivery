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
  String get butlerDetailsTitle => 'تفاصيل المهمة';

  @override
  String get butlerViewDetails => 'عرض التفاصيل';

  @override
  String get butlerCancelErrand => 'إلغاء المهمة';

  @override
  String get butlerCancelConfirmTitle => 'هل تريد إلغاء هذه المهمة؟';

  @override
  String get butlerCancelConfirmBody =>
      'ستُسحب فورًا ولن يذهب أحد لتنفيذها. يمكنك طلبها مجددًا في أي وقت.';

  @override
  String get butlerCancelConfirmYes => 'نعم، ألغِها';

  @override
  String get butlerTrackOrder => 'تتبّع الطلب';

  @override
  String get butlerDetailProgress => 'سير المهمة';

  @override
  String get butlerDetailTheErrand => 'المهمة';

  @override
  String get butlerDetailWhereFrom => 'من أين';

  @override
  String get butlerDetailRecipient => 'من سيستلمها';

  @override
  String get butlerDetailContactPhone => 'هاتف التواصل';

  @override
  String get butlerDetailPrice => 'السعر';

  @override
  String get butlerDetailBudgetCap => 'سقف ميزانيتك';

  @override
  String get butlerDetailGoods => 'المشتريات';

  @override
  String get butlerDetailGoodsPending => 'يُعرف بعد أن يدفع المتسوّق';

  @override
  String get butlerDetailErrandFee => 'رسوم المهمة';

  @override
  String get butlerDetailTotal => 'الإجمالي المستحق';

  @override
  String get butlerDetailReceipt => 'رقم الإيصال';

  @override
  String butlerDeclineReason(String reason) {
    return 'السبب: $reason';
  }

  @override
  String get butlerStepRequested => 'تم إرسال الطلب';

  @override
  String get butlerStepClaimedBuy => 'تولّاها متسوّق';

  @override
  String get butlerStepClaimedSend => 'تولّاها سائق';

  @override
  String get butlerStepQuoted => 'تم تحديد السعر';

  @override
  String get butlerStepAgreed => 'تم الاتفاق على السعر';

  @override
  String get butlerStepConfirmed => 'تم التأكيد';

  @override
  String get butlerStepClaimBuyPending => 'بانتظار متسوّق';

  @override
  String get butlerStepClaimSendPending => 'بانتظار سائق';

  @override
  String get butlerStepQuotePending => 'يخبرك المتسوّق بالسعر';

  @override
  String get butlerStepAgreePending => 'توافق على السعر';

  @override
  String get butlerStepConfirmPending => 'تؤكّد الرسوم';

  @override
  String get butlerStepStateDone => 'تم';

  @override
  String get butlerStepStateNow => 'الآن';

  @override
  String get butlerStepStateNext => 'لم يحن بعد';

  @override
  String get butlerStepStateEnded => 'انتهت';

  @override
  String get butlerDetailQuotedTotal => 'الإجمالي المعروض';

  @override
  String butlerConfirmFee(String amount) {
    return 'تأكيد $amount';
  }

  @override
  String get butlerSendConfirmed => 'تم التأكيد. سيأتي السائق لاستلامها.';

  @override
  String butlerSendAwaitingConfirm(String fee) {
    return 'تولّاها سائق. أكّد رسوم $fee وسيأتي لاستلامها.';
  }

  @override
  String get butlerDeclineConfirmTitle => 'هل تريد رفض هذا السعر؟';

  @override
  String get butlerDeclineConfirmBody =>
      'تنتهي المهمة هنا ولا يمكن إعادة فتحها. لقد دفع المتسوّق ثمن المشتريات بالفعل.';

  @override
  String get butlerDeclineConfirmYes => 'نعم، ارفض';

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
  String couldNotOpenPicker(Object reason) {
    return 'تعذّر فتح منتقي الملفات: $reason';
  }

  @override
  String uploadFailedBecause(Object reason) {
    return 'فشل الرفع: $reason';
  }

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
  String get merchbAddPhotosNow => 'أضف الصور الآن — تُرفع عند الحفظ.';

  @override
  String get merchbPhotosAddedOnSave => 'تُضاف هذه الصور عند الحفظ.';

  @override
  String get merchbPending => 'قيد الإضافة';

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
  String get authJoinYoudrop => 'انضم إلى YouDrop';

  @override
  String get authChooseHowToUse => 'اختر طريقة استخدامك لـ YouDrop';

  @override
  String get authRolePopular => 'شائع';

  @override
  String get authRoleWantOrder => 'أريد أن أطلب';

  @override
  String get authRoleWantOrderBlurb => 'احصل على الطعام والبقالة والطرود بسرعة';

  @override
  String get authRoleWantDeliver => 'أريد أن أوصّل';

  @override
  String get authRoleWantDeliverBlurb => 'اعمل وفق جدولك واحتفظ بكامل البقشيش';

  @override
  String get authRoleWantSell => 'أريد أن أبيع';

  @override
  String get authRoleWantSellBlurb => 'طوّر مطعمك أو متجرك';

  @override
  String get riderIntroHeader => 'قدّم كشريك';

  @override
  String get riderIntroTitle => 'اكسب وفق جدولك';

  @override
  String get riderIntroSubtitle =>
      'انضم إلى أفضل أسطول توصيل في لبنان. قُد سكوتر أو دراجة نارية أو سيارة، وابدأ الكسب اليوم.';

  @override
  String get riderPerk1Title => 'قُد في وقتك الخاص';

  @override
  String get riderPerk1Body => 'لا حدّ أدنى للساعات، ورديات مرنة تماماً.';

  @override
  String get riderPerk2Title => 'دفعات سريعة نقداً وبالدولار';

  @override
  String get riderPerk2Body => 'احصل على أجرك يومياً أو أسبوعياً نقداً مباشرة.';

  @override
  String get riderPerk3Title => 'مكافآت وقود للسائقين';

  @override
  String get riderPerk3Body => 'استفد من محطات وقود بأسعار مخفّضة في كل لبنان.';

  @override
  String get applyToDeliver => 'قدّم للتوصيل';

  @override
  String get merchantIntroHeader => 'انمُ معنا';

  @override
  String get merchantIntroHeaderLogin => 'شريك بالفعل؟';

  @override
  String get merchantIntroTitle => 'نمِّ عملك';

  @override
  String get merchantIntroSubtitle =>
      'اعمل مع YouDrop وقدّم توصيلاً سريعاً أو طلبات خارجية لسكان بيروت وكل لبنان.';

  @override
  String get merchantBenefit1Title => 'الوصول إلى أكثر من 50,000 زبون';

  @override
  String get merchantBenefit1Body => 'ظهور فوري للزبائن الجائعين ضمن نطاقك.';

  @override
  String get merchantBenefit2Title => 'بدون رسوم إعداد وقوائم سهلة';

  @override
  String get merchantBenefit2Body =>
      'فريقنا يبني وينسّق قائمتك أو كتالوج متجرك على الإنترنت.';

  @override
  String get merchantBenefit3Title => 'دفعات مباشرة ولوحة تحكّم';

  @override
  String get merchantBenefit3Body =>
      'تابع المبيعات والطلبات واسحب النقد لحظياً.';

  @override
  String get registerStoreNow => 'سجّل متجرك الآن';

  @override
  String get authAlreadyHaveAnAccount => 'لديك حساب بالفعل؟';

  @override
  String get authDontHaveAnAccount => 'ليس لديك حساب؟';

  @override
  String get authSignUp => 'أنشئ حساباً';

  @override
  String get authSignInSubtitle => 'أدخل بياناتك لتسجيل الدخول.';

  @override
  String get authSignInAccountSubtitle => 'سجّل الدخول إلى حسابك على YouDrop';

  @override
  String get authTaglineLebanon => 'وصّل كل شيء في لبنان';

  @override
  String get authLogIn => 'تسجيل الدخول';

  @override
  String get authForgotShort => 'نسيت؟';

  @override
  String authSocialComingSoon(String provider) {
    return 'تسجيل الدخول عبر $provider قادم قريباً.';
  }

  @override
  String authStepOf(int current, int total) {
    return 'الخطوة $current من $total';
  }

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
  String get authZonesNoneToPickTitle => 'لا توجد مناطق للاختيار';

  @override
  String get authZonesNoneToPickBlurb =>
      'لا يُربط السائق بمنطقة ثابتة على هذه المنصة. ما يعتمد عليه المراجع هو الدبوس الذي وضعته والمنطقة التي كتبتها أعلاه.';

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
  String custSearchInCategory(String name) {
    return 'ابحث في $name';
  }

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
  String get custProductDetails => 'تفاصيل المنتج';

  @override
  String get custYourOrders => 'طلباتك';

  @override
  String custActiveOrdersTab(int count) {
    return 'الطلبات الجارية ($count)';
  }

  @override
  String get custPastOrdersTab => 'الطلبات السابقة';

  @override
  String custItemsCountLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر',
      many: '$count عنصرًا',
      few: '$count عناصر',
      two: 'عنصران',
      one: 'عنصر واحد',
      zero: 'لا عناصر',
    );
    return '$_temp0';
  }

  @override
  String get custReorder => 'أعد الطلب';

  @override
  String get custActiveStoresNearby => 'متاجر نشطة قريبة';

  @override
  String custShowingShops(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count متجر',
      many: '$count متجرًا',
      few: '$count متاجر',
      two: 'متجرين',
      one: 'متجر واحد',
    );
    return 'عرض $_temp0';
  }

  @override
  String get custSortFilter => 'الترتيب / التصفية';

  @override
  String get custTrackConfirmed => 'مؤكَّد';

  @override
  String get custTrackPreparing => 'قيد التحضير';

  @override
  String get custTrackOnTheWay => 'في الطريق';

  @override
  String get custTrackDelivered => 'تم التوصيل';

  @override
  String get custButlerBanner => 'نشتري أو نوصّل أي شيء!';

  @override
  String get custButlerBannerBlurb =>
      'نسيت شيئاً؟ تحتاج استلام مفاتيح أو شراء من متجر غير مدرج؟ صِفه وسيُنجزه سائق YouDrop.';

  @override
  String custPlatformRate(String rate) {
    return 'سعر المنصة: 1\$ = $rate ل.ل.';
  }

  @override
  String get custRateLocked =>
      'سعر مثبّت — مبلغ الليرة الذي توافق عليه هو ما يُحصَّل.';

  @override
  String get custSplitPayment => 'الدفع اللبناني المقسّم';

  @override
  String get custSplitBlurb =>
      'اخلط أوراقك! ادفع جزءاً بالدولار النقدي والباقي بالليرة اللبنانية.';

  @override
  String get custPayInUsd => 'ادفع بالدولار النقدي';

  @override
  String get custPayInLbp => 'ادفع بالليرة (ل.ل.)';

  @override
  String custRiderChange(String amount) {
    return 'السائق يحمل فراطة حتى $amount ل.ل. ودولار نقدي.';
  }

  @override
  String get custLocalPaymentMethods => 'طرق الدفع المحلية';

  @override
  String get custCashUsdLbp => 'نقداً عند التسليم (دولار/ليرة)';

  @override
  String get custWhishTransfer => 'تحويل Whish Money';

  @override
  String get custOmtTransfer => 'تحويل OMT';

  @override
  String custPlaceOrderAmount(String amount) {
    return 'إتمام الطلب ($amount)';
  }

  @override
  String custPctUsd(int pct) {
    return '$pct٪ دولار';
  }

  @override
  String custPctLbp(int pct) {
    return '$pct٪ ليرة';
  }

  @override
  String get custPowerMains => 'كهرباء الدولة';

  @override
  String get custPowerGenerator => 'مولّد';

  @override
  String get custPowerDark => 'مقطوعة حالياً';

  @override
  String get custGeneratorBanner => 'ساعات المولّد — قد يتأخر التوصيل قليلاً';

  @override
  String get custDarkBanner =>
      'الكهرباء مقطوعة عن المحل الآن — قد ينتظر طلبك عودتها';

  @override
  String custContinueAs(String name) {
    return 'تابع باسم $name';
  }

  @override
  String get custNotYou => 'لست أنت؟ سجّل الدخول بحساب آخر';

  @override
  String get custBioExpired => 'انتهت صلاحية الدخول المحفوظ — أدخل رمزك السري.';

  @override
  String get carrForCarriers => 'لشركات التوصيل';

  @override
  String get carrPartnerTitle => 'كن شريك YouDrop';

  @override
  String get carrPartnerBlurb =>
      'نمِّ شركة التوصيل الخاصة بك في كل لبنان عبر محرك اللوجستيات الموحد للشركات.';

  @override
  String get carrBenefitOrders => 'طلبات يومية مضمونة';

  @override
  String get carrBenefitOrdersBlurb =>
      'وصول فوري إلى تدفق طلبات الشركاء المحليين.';

  @override
  String get carrBenefitTracking => 'تتبع الأسطول لحظياً';

  @override
  String get carrBenefitTrackingBlurb => 'لوحة ذكية لتحسين المسارات والإرسال.';

  @override
  String get carrBenefitPayouts => 'دفعات أسبوعية بالدولار النقدي';

  @override
  String get carrBenefitPayoutsBlurb => 'تكاملات مالية موثوقة مع تسويات فورية.';

  @override
  String get carrRegisterCompany => 'سجّل شركتك';

  @override
  String get carrChoiceCard => 'أدير شركة توصيل';

  @override
  String get carrChoiceCardBlurb => 'أحضر أسطولك ووزّع طلبات YouDrop';

  @override
  String get carrCompanyInformation => 'معلومات الشركة';

  @override
  String get carrCompanyInformationBlurb => 'مع من توقّع المنصة.';

  @override
  String get carrCompanyName => 'اسم الشركة';

  @override
  String get carrCompanyNameHint => 'مثال: بيروت إكسبرس للتوصيل';

  @override
  String get carrCrNumber => 'رقم السجل التجاري';

  @override
  String get carrCompanyType => 'نوع الشركة';

  @override
  String get carrFleetSizeBand => 'حجم الأسطول';

  @override
  String get carrCoverageArea => 'مناطق التغطية (لبنان)';

  @override
  String get carrContactPerson => 'الشخص المسؤول';

  @override
  String get carrFleetDetails => 'تفاصيل الأسطول والمركبات';

  @override
  String get carrFleetDetailsBlurb => 'ما يستطيع أسطولك حمله فعلاً.';

  @override
  String get carrActiveVehicles => 'عدد المركبات العاملة';

  @override
  String get carrMotorcycles => 'دراجات نارية';

  @override
  String get carrCars => 'سيارات';

  @override
  String get carrVans => 'فانات';

  @override
  String get carrTrucks => 'شاحنات';

  @override
  String get carrOperatingHours => 'ساعات العمل';

  @override
  String get carrWeekdays => 'أيام الأسبوع';

  @override
  String get carrWeekends => 'نهاية الأسبوع';

  @override
  String get carrCapabilities => 'قدرات الأسطول';

  @override
  String get carrCapColdChain => 'سلسلة تبريد بمولّد';

  @override
  String get carrCapFood => 'دعم توصيل الطعام';

  @override
  String get carrCapGrocery => 'دعم توصيل البقالة';

  @override
  String get carrCapPharmacy => 'دعم توصيل الصيدلية';

  @override
  String get carrCapParcel => 'دعم توصيل الطرود';

  @override
  String get carrCapButler => 'خدمات بتلر مخصصة';

  @override
  String get carrPayoutSetup => 'الدفعات والإعداد المالي';

  @override
  String get carrPayoutSetupBlurb => 'كيف تُدفع شركتك.';

  @override
  String get carrCommissionRate => 'نسبة العمولة';

  @override
  String get carrPayoutSchedule => 'جدول الدفعات';

  @override
  String get carrEveryMonday => 'كل يوم اثنين';

  @override
  String get carrAgreement =>
      'أوافق على اتفاقية شراكة وخدمة YouDrop للناقلين. نسب العمولة وفترات الدفع خاضعة لتدقيق حجم شهري.';

  @override
  String get carrSubmitApplication => 'أرسل الطلب';

  @override
  String get carrDashboard => 'اللوحة';

  @override
  String get carrOrdersTab => 'الطلبات';

  @override
  String get carrFleetTab => 'الأسطول';

  @override
  String get carrEarningsTab => 'الأرباح';

  @override
  String get carrSettingsTab => 'الإعدادات';

  @override
  String get carrActiveDeliveries => 'توصيلات جارية';

  @override
  String get carrPendingOrders => 'طلبات منتظرة';

  @override
  String get carrRidersOnline => 'سائقو الأسطول';

  @override
  String carrWindowEarned(int days) {
    return 'المكتسب ($days يوم)';
  }

  @override
  String get carrRecentActivity => 'النشاط الأخير';

  @override
  String get carrFleetManagement => 'إدارة الأسطول';

  @override
  String carrDeliveriesToday(int count) {
    return '$count توصيلة في الفترة';
  }

  @override
  String get carrCall => 'اتصل';

  @override
  String get carrTotalRevenue => 'إجمالي الإيرادات';

  @override
  String get carrNetEarnings => 'صافي الأرباح';

  @override
  String get carrCommissionPaid => 'العمولة المدفوعة لYouDrop';

  @override
  String get carrCompanyPaused => 'الشركة متوقفة — لا يُعرض عمل جديد';

  @override
  String get carrPauseCompany => 'أوقف الشركة مؤقتاً';

  @override
  String get carrResumeCompany => 'استأنف الشركة';

  @override
  String get carrScore => 'تقييم الناقل';

  @override
  String get carrCompletionRate => 'نسبة الإكمال';

  @override
  String get carrOrdersDelivered => 'طلبات موصلة';

  @override
  String get carrAlreadyPartner => 'شريك معنا من قبل؟';

  @override
  String get carrBusinessEmail => 'البريد الإلكتروني للشركة';

  @override
  String get carrBusinessEmailHint => 'partner@company.com';

  @override
  String get carrContactPersonHint => 'الاسم الكامل لممثل الشركة';

  @override
  String get carrPhoneHint => '+961 70 123 456';

  @override
  String get carrDocsTitle => 'رفع مستندات التحقق';

  @override
  String get carrVerificationNote =>
      'تُراجع المستندات من قبل مكتب عمليات YouDrop. يكتمل التحقق عادةً خلال 24–48 ساعة.';

  @override
  String get carrPayoutMethod => 'طريقة الدفع المفضلة';

  @override
  String get carrPayoutCash => 'دولار نقدي (استلام من المكتب)';

  @override
  String get carrPayoutCashBlurb => 'بدون رسوم خدمة، تسوية نقدية أسبوعية';

  @override
  String get carrPayoutWhish => 'تحويل Whish Money';

  @override
  String get carrPayoutWhishBlurb => 'دفع عبر المحفظة اللبنانية المعتادة';

  @override
  String get carrPayoutOmt => 'سحب نقدي OMT';

  @override
  String get carrPayoutOmtBlurb => 'الدفع مباشرةً عبر شبكة OMT';

  @override
  String get carrPayoutBank => 'حوالة مصرفية بالدولار';

  @override
  String get carrPayoutBankBlurb => 'حوالة دولار نقدي إلى حساب مصرفي لبناني';

  @override
  String carrFlatFee(int rate) {
    return '$rate% رسم ثابت';
  }

  @override
  String get carrSubmittedTitle => 'تم إرسال الطلب!';

  @override
  String carrAppId(String reference) {
    return 'رقم الطلب: $reference';
  }

  @override
  String get carrApplicationStatus => 'حالة الطلب';

  @override
  String get carrStageReceived => 'استلمنا الطلب';

  @override
  String carrStageReceivedSub(String date) {
    return 'أُرسل في $date';
  }

  @override
  String get carrStageDocs => 'التحقق من المستندات';

  @override
  String get carrStageDocsSub => 'قيد المراجعة (خلال 24–48 ساعة)';

  @override
  String get carrStageInspection => 'معاينة الأسطول';

  @override
  String get carrStageInspectionSub => 'تُحدد في مرأب مركباتكم';

  @override
  String get carrStageActivation => 'تفعيل الحساب';

  @override
  String get carrStageActivationSub => 'الوصول إلى منصة توزيع YouDrop للناقلين';

  @override
  String get carrPendingSupportBlurb =>
      'أرسلنا لك بريداً للتأكيد. تحتاج مساعدة عاجلة بخصوص طلبك؟';

  @override
  String get carrChatSupport => 'تحدث مع دعم الشركاء';

  @override
  String get carrReturnHome => 'العودة إلى الرئيسية';

  @override
  String get carrBadgeLive => 'مباشر';

  @override
  String get carrBadgeWaiting => 'بالانتظار';

  @override
  String get carrBadgeFleet => 'أسطول';

  @override
  String get carrBadgeUsd => 'دولار';

  @override
  String get carrTodayRevenue => 'إيراد اليوم';

  @override
  String get carrCoverageMapBlurb =>
      'الدوائر التي يعمل فيها سائقوكم. اضغط للتعديل.';

  @override
  String get carrIncoming => 'واردة';

  @override
  String get carrCompleted => 'مكتملة';

  @override
  String get carrUnassigned => 'طلب غير مُسند';

  @override
  String get carrWaitingDispatch => 'بانتظار الإسناد';

  @override
  String carrShowingRiders(int count) {
    return '$count سائقاً في الأسطول';
  }

  @override
  String get carrNoRiders =>
      'لا سائقين في الأسطول بعد — تُسند المنصة السائقين بعد التسجيل.';

  @override
  String carrDelivering(String id) {
    return 'يوصل #$id';
  }

  @override
  String get carrAvailable => 'متاح';

  @override
  String get carrWeeklySummary => 'ملخص الأسبوع';

  @override
  String get carrDeliveriesBreakdown => 'تفصيل التوصيلات';

  @override
  String carrCommissionPct(int rate) {
    return 'عمولة YouDrop ($rate%)';
  }

  @override
  String get carrNextPayout => 'الدفعة القادمة';

  @override
  String get carrPickupFrom => 'الاستلام من';

  @override
  String get carrDeliverTo => 'التوصيل إلى';

  @override
  String get carrPaymentCommission => 'الدفع والعمولة';

  @override
  String get carrDeliveryFee => 'إجمالي التوصيل (دولار نقدي)';

  @override
  String carrLbpRate(String rate) {
    return 'سعر التحويل بالليرة ($rate)';
  }

  @override
  String carrPlatformFee(int rate) {
    return 'رسوم منصة YouDrop ($rate%)';
  }

  @override
  String get carrStepReceived => 'استُلم';

  @override
  String get carrStepAssigned => 'أُسند';

  @override
  String get carrStepPickingUp => 'قيد الاستلام';

  @override
  String get carrStepEnRoute => 'في الطريق';

  @override
  String get carrStepDelivered => 'وصل';

  @override
  String get carrOperations => 'العمليات';

  @override
  String get carrPayments => 'الدفعات';

  @override
  String get carrAccountSection => 'الحساب';

  @override
  String get carrHelpSupport => 'المساعدة والدعم';

  @override
  String carrVersionCaption(String version) {
    return 'YouDrop للناقلين، إصدار $version';
  }

  @override
  String get carrCoverageZones => 'مناطق التغطية';

  @override
  String get carrAddZone => 'أضف منطقة';

  @override
  String get carrZoneName => 'اسم المنطقة';

  @override
  String get carrZoneNameHint => 'مثلاً: وسط بيروت';

  @override
  String carrZoneRadiusKm(String km) {
    return 'نصف القطر: $km كلم';
  }

  @override
  String get carrZoneActive => 'فعالة';

  @override
  String get carrZonePaused => 'موقوفة';

  @override
  String carrDeleteZoneAsk(String name) {
    return 'حذف $name؟ يبقى السائقون يعملون في بقية المناطق.';
  }

  @override
  String get carrNoZones => 'لا مناطق بعد. ارسم أول دائرة يعمل فيها سائقوكم.';

  @override
  String get carrEditZone => 'تعديل المنطقة';

  @override
  String get carrNewZone => 'منطقة جديدة';

  @override
  String get custVerifiedLocal => 'محل موثوق';

  @override
  String get custPowerDeclared => 'حالة الكهرباء — كما أعلنتها المحلات نفسها';

  @override
  String get merchbPowerHeading => 'حالة الكهرباء';

  @override
  String get merchbPowerHint =>
      'أخبر الزبائن ماذا تفعل الكهرباء — تظهر على بطاقة متجرك.';

  @override
  String get merchbDeliveryAreaOff => 'لا حدّ للتوصيل — المناطق وحدها تقرر';

  @override
  String merchbDeliverWithin(String km) {
    return 'التوصيل ضمن $km كم';
  }

  @override
  String custOutsideDeliveryArea(String store, String km) {
    return '$store يوصّل ضمن $km كم من المتجر — هذا العنوان خارج نطاقه.';
  }

  @override
  String get custHyperlocalTitle => 'دكانة الحي';

  @override
  String get custHyperlocalSub => 'محلات شوارعك المحلية';

  @override
  String get custDistricts => 'المناطق';

  @override
  String get custSearchArabiziHint => 'ابحث: قهوة، منقوشة، كنافة...';

  @override
  String get custAllDistricts => 'كل المناطق';

  @override
  String get custDiasporaSub => 'بوابة هدايا المغتربين';

  @override
  String get custPersonalNoteHint =>
      'حبيبتي ماما، أتمنى لك أسبوعاً جميلاً — بعض الطعام والبقالة مع حبي!';

  @override
  String get custWhatToSend => 'ماذا تحب أن ترسل؟';

  @override
  String custRecentDeliveriesTo(String name) {
    return 'توصيلات سابقة إلى $name';
  }

  @override
  String get custStartOrder => 'اختر المنتجات وابدأ الطلب';

  @override
  String get custPickRecipient => 'اختر من يستلم';

  @override
  String get custNoRecipientYet =>
      'احفظ عنوانهم أولاً — أضفه من دفتر العناوين واجعل الاسم هو التسمية.';

  @override
  String get custGiftNoteRides => 'رسالتك تسافر مع الطلب وتُقرأ عند الباب.';

  @override
  String get you => 'أنت';

  @override
  String get custSoloOrder => 'طلب فردي';

  @override
  String get custSplitOrder => 'طلب مشترك';

  @override
  String get custOrderParticipants => 'المشاركون في الطلب';

  @override
  String get custAddFriend => 'أضف صديقاً';

  @override
  String custAssignedTo(String name) {
    return 'على حساب: $name';
  }

  @override
  String get custPaymentSplitSummary => 'ملخص تقسيم الدفع';

  @override
  String get custTotalOrderAmount => 'إجمالي الطلب';

  @override
  String get custSendPaymentRequests => 'أرسل طلبات الدفع';

  @override
  String get custSplitWithGroup => 'قسّم مع المجموعة';

  @override
  String get custHowManyPeople => 'كم شخصاً؟';

  @override
  String get custIncludingYourself => 'بمن فيهم أنت';

  @override
  String get custEvenBreakdown => 'التقسيم بالتساوي';

  @override
  String get custEachPays => 'كل واحد يدفع';

  @override
  String custHostAbsorbs(String amount) {
    return 'المضيف يتحمل الباقي $amount';
  }

  @override
  String get custAddFriendsHdr => 'أضف الأصدقاء';

  @override
  String get custEnterUsername => 'اكتب اسم المستخدم';

  @override
  String get custYourShareYou => 'حصتك (أنت)';

  @override
  String get cust15MinNote => 'أمام أصدقائك 15 دقيقة للدفع بعد الدعوة';

  @override
  String get custSendInvites => 'أرسل الدعوات';

  @override
  String get custWaitingGroupPayments => 'بانتظار دفعات المجموعة';

  @override
  String get custTimeRemaining => 'الوقت المتبقي';

  @override
  String custSplitNWays(String amount, int n) {
    return '$amount مقسومة على $n';
  }

  @override
  String get custPaymentProgress => 'تقدم الدفع';

  @override
  String custNPaid(int paid, int total) {
    return 'دفع $paid من $total';
  }

  @override
  String custCollectedOf(String collected, String total) {
    return 'جُمع $collected من $total';
  }

  @override
  String custPaidVia(String method) {
    return 'دفع عبر $method';
  }

  @override
  String get custPaidChip => 'مدفوع';

  @override
  String get custPendingChip => 'بالانتظار';

  @override
  String get custDeclinedChip => 'رفض';

  @override
  String get custCoveredChip => 'غطّاه المضيف';

  @override
  String custCoverRest(String amount) {
    return 'غطِّ الباقي ($amount)';
  }

  @override
  String get custReadyToPlace => 'اكتملت الحصص — أتمم الطلب';

  @override
  String get custContinueToCheckout => 'تابع إلى الدفع';

  @override
  String get custRemindBtn => 'ذكّر';

  @override
  String get custCancelSplit => 'ألغِ الطلب المشترك';

  @override
  String custInvitedYouToSplit(String name) {
    return '$name دعاك لمشاركة طلب';
  }

  @override
  String get custYourShareToPay => 'حصتك للدفع';

  @override
  String get custSelectPaymentMethod => 'اختر طريقة الدفع';

  @override
  String get custWhishShort => 'Whish Money';

  @override
  String get custOmtShort => 'OMT';

  @override
  String get custBobShort => 'BOB Finance';

  @override
  String get custCashAtDoor => 'نقداً عند الباب';

  @override
  String get custRiderCollectsFromYou => 'السائق سيحصّلها منك';

  @override
  String get custRecommendedChip => 'موصى بها';

  @override
  String custPayMyShare(String amount) {
    return 'ادفع حصتي ($amount)';
  }

  @override
  String get custDeclineInvitation => 'ارفض الدعوة';

  @override
  String get custAllSharesPaid => 'دُفعت كل الحصص!';

  @override
  String get custGroupSplitSummary => 'ملخص المجموعة';

  @override
  String custRiderCollectNote(String amount, String name) {
    return 'السائق سيحصّل $amount من $name عند التسليم';
  }

  @override
  String get custAddToOrder => 'أضف إلى الطلب';

  @override
  String get custSearchByUsername => 'ابحث باسم المستخدم...';

  @override
  String get custRecentlySplitWith => 'شاركت معهم مؤخراً';

  @override
  String get custQuickAdd => 'إضافة سريعة';

  @override
  String custAddAsGuest(String name) {
    return 'أضف $name كضيف — يدفع نقداً عند الباب';
  }

  @override
  String custSplitRequestBanner(String name) {
    return '$name دعاك لمشاركة طلب';
  }

  @override
  String get custPayYourShare => 'ادفع حصتك';

  @override
  String get riderCashChecklist => 'قائمة تحصيل النقد';

  @override
  String get riderAlreadyPaid => 'مدفوع رقمياً';

  @override
  String get riderTotalCashCollect => 'إجمالي النقد للتحصيل';

  @override
  String get riderSplitOrderTag => 'طلب مشترك';

  @override
  String custMinOrderLine(String amount) {
    return 'الحد الأدنى للطلب: $amount';
  }

  @override
  String custYesterdayAt(String time) {
    return 'أمس، $time';
  }

  @override
  String get custDualPriceMode => 'سعر بعملتين';

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
  String custHiName(String name) {
    return 'أهلاً $name';
  }

  @override
  String get custRewardsTitle => 'المكافآت والنقاط';

  @override
  String get custTotalPoints => 'مجموع النقاط';

  @override
  String custPtsThisMonth(int points) {
    return '+$points نقطة هذا الشهر';
  }

  @override
  String custNextTierLabel(String tier) {
    return 'الفئة التالية: $tier';
  }

  @override
  String custPtsToGo(int points) {
    return 'بقي $points نقطة';
  }

  @override
  String get custRewardsBlurb =>
      'اكسب نقاطاً على كل طلب يُوصَل. استبدلها بقسائم واسترداد نقدي.';

  @override
  String get custCurrentTierHeading => 'فئتك الحالية';

  @override
  String custCurrentTierLine(String tier) {
    return 'الفئة الحالية: $tier';
  }

  @override
  String custTierEarnedLine(int points, int orders) {
    return 'كسبت $points نقطة · $orders طلبات مكتملة';
  }

  @override
  String custNextTierLine(String tier) {
    return 'الفئة التالية: $tier';
  }

  @override
  String custNextTierBlurb(int points) {
    return 'اجمع $points نقطة لفتح مكافآت أفضل.';
  }

  @override
  String get custTopTier => 'أنت في أعلى فئة.';

  @override
  String get custRewardCategories => 'فئات المكافآت';

  @override
  String get custFreeDelivery => 'توصيل مجاني';

  @override
  String get custVouchersAvailable => 'قسائم متاحة';

  @override
  String get custCashback => 'استرداد نقدي';

  @override
  String get custEarnedLabel => 'المكتسب';

  @override
  String get custReferralBonus => 'مكافأة الإحالة';

  @override
  String get custRecentActivity => 'النشاط الأخير';

  @override
  String get custNoActivityYet => 'لا نقاط بعد — تصلك مع أول طلب يُوصَل.';

  @override
  String custPointsOrderEntry(String points, String shortId) {
    return '$points نقطة · طلب #$shortId';
  }

  @override
  String custPointsEntry(String points) {
    return '$points نقطة';
  }

  @override
  String get tierBronze => 'برونزية';

  @override
  String get tierSilver => 'فضية';

  @override
  String get tierGold => 'ذهبية';

  @override
  String get tierPlatinum => 'بلاتينية';

  @override
  String get custMyAccount => 'حسابي';

  @override
  String get custMyOrders => 'طلباتي';

  @override
  String get custMyAddresses => 'عناويني';

  @override
  String get custPaymentMethods => 'طرق الدفع';

  @override
  String get custVouchersPromos => 'القسائم والعروض';

  @override
  String get custPreferences => 'التفضيلات';

  @override
  String get custSupport => 'الدعم';

  @override
  String get custTermsPrivacy => 'الشروط والخصوصية';

  @override
  String get custAboutYoudrop => 'حول YouDrop';

  @override
  String get custEditProfile => 'تعديل الملف الشخصي';

  @override
  String get custLogOutAccount => 'تسجيل الخروج من الحساب';

  @override
  String get custAppLanguage => 'لغة التطبيق';

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
  String get merchbHideShop => 'إخفاء المتجر';

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
  String get merchbSearchMenuItems => 'ابحث في المنتجات...';

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
  String get merchbUploadImageCta => 'ارفع صورة المنتج';

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
  String get merchbOptionsNeedSave => 'احفظ الصنف أولاً، ثم أضف خياراته.';

  @override
  String get merchbOptionsLoadFailed =>
      'تعذّر تحميل الخيارات الحالية. لم يتم تغيير أي شيء.';

  @override
  String get merchbOptionsSaveFailed => 'تعذّر حفظ الخيارات.';

  @override
  String get merchbAddGroup => '+ أضف مجموعة';

  @override
  String get merchbGroupName => 'اسم المجموعة';

  @override
  String get merchbRemoveGroup => 'حذف المجموعة';

  @override
  String get merchbOptionName => 'الخيار';

  @override
  String get merchbRemoveOption => 'حذف الخيار';

  @override
  String get merchbPriceDelta => 'الفرق بالسعر';

  @override
  String get merchbMinSelect => 'اختر على الأقل';

  @override
  String get merchbMaxSelect => 'اختر بحد أقصى';

  @override
  String get merchbRuleRequired => 'إلزامي — على الزبون أن يختار.';

  @override
  String get merchbRuleOptional => 'اختياري — يمكن للزبون تخطّيه.';

  @override
  String get merchbUntitledGroup => 'هذه المجموعة';

  @override
  String get merchbGroupNeedsName => 'كل مجموعة تحتاج إلى اسم.';

  @override
  String merchbGroupNeedsOption(String name) {
    return '$name تحتاج إلى خيار واحد على الأقل.';
  }

  @override
  String merchbOptionNeedsName(String name) {
    return 'كل خيار في $name يحتاج إلى اسم.';
  }

  @override
  String merchbMinAboveMax(String name) {
    return 'في $name، الحد الأدنى أكبر من الحد الأقصى.';
  }

  @override
  String merchbMinAboveCount(String name) {
    return 'في $name، الحد الأدنى أكبر من عدد الخيارات.';
  }

  @override
  String merchbGroupOutOfRange(String name) {
    return 'في $name، يجب أن تكون الأرقام بين 0 و50.';
  }

  @override
  String get merchbSaveMenuItem => 'حفظ المنتج';

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
  String get merchbBankReadOnly =>
      'هذا هو الحساب المسجَّل. حُدِّد مع طلبك، وفريق المنصة هو من يغيّره الآن — لا هذه الشاشة.';

  @override
  String get merchbBankNoneFiled =>
      'لم تُسجَّل بيانات بنكية مع طلبك. تُغلق خطوة البيانات البنكية بعد البتّ في الطلب، لذا فريق المنصة هو من يضيفها الآن.';

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

  @override
  String get etaWaitingFirstFix => 'بانتظار أول إشارة GPS من السائق';

  @override
  String get etaPositionOutOfDate => 'موقع السائق غير محدَّث';

  @override
  String get etaNoMapPoint => 'لا توجد نقطة على الخريطة للقياس إليها';

  @override
  String get etaRouteServiceDown => 'خدمة المسارات لم تستجب';

  @override
  String get etaNothingOnItsWay => 'لا يوجد شيء في الطريق';

  @override
  String get etaUnavailable => 'لا يتوفر تقدير للوصول';

  @override
  String get etaHeadingToShop => 'في الطريق إلى المتجر';

  @override
  String get etaOnTheWayToYou => 'في الطريق إليك';

  @override
  String get etaStraightLineNote =>
      'تقدير تقريبي — يُقاس بخط مستقيم لا عبر الطرقات';

  @override
  String get dutyOnDuty => 'على رأس العمل';

  @override
  String get dutyOffDuty => 'خارج الدوام';

  @override
  String get presenceSignalLost => 'انقطعت الإشارة';

  @override
  String get promoApplied => 'تم تطبيق الرمز';

  @override
  String get promoUnknownCode => 'الرمز غير معروف';

  @override
  String get promoNotActive => 'هذا الرمز لم يعد متاحاً';

  @override
  String get promoNotStarted => 'لا يمكن استخدام هذا الرمز بعد';

  @override
  String get promoExpired => 'انتهت صلاحية هذا الرمز';

  @override
  String get promoBelowMinimum => 'سلّتك أقل من الحد الأدنى لهذا الرمز';

  @override
  String get promoFullyRedeemed => 'استُنفد هذا الرمز بالكامل';

  @override
  String get promoAlreadyUsed => 'سبق أن استخدمت هذا الرمز';

  @override
  String get promoWorthNothing => 'لا قيمة لهذا الرمز على هذا الطلب';

  @override
  String get promoDidNotApply => 'لم يُطبَّق هذا الرمز';

  @override
  String get paymentWallet => 'المحفظة';

  @override
  String get paymentTestModeNote =>
      'دفعة تجريبية — لا يُحوَّل أي مال حقيقي في هذه النسخة';

  @override
  String get cashOutRequested => 'مطلوب';

  @override
  String get cashOutPaid => 'مدفوع';

  @override
  String get cashOutRefused => 'مرفوض';

  @override
  String get paidByPlatform => 'تدفعها المنصة';

  @override
  String get paidByYourCompany => 'تدفعها شركتك';

  @override
  String get paidElsewhere => 'تُدفع خارج المنصة';

  @override
  String get tipCashAtDoor => 'نقداً عند الباب';

  @override
  String get tipOnline => 'عبر الإنترنت';

  @override
  String get docNationalId => 'الهوية الوطنية';

  @override
  String get docDrivingLicence => 'رخصة القيادة';

  @override
  String get docVehicleRegistration => 'أوراق المركبة';

  @override
  String get docCommercialRegistration => 'السجل التجاري';

  @override
  String get docTradeLicence => 'رخصة تجارية (مصدّقة)';

  @override
  String get docFleetInsurance => 'شهادة تأمين الأسطول';

  @override
  String get docFleetRegistration => 'تسجيلات السائقين والأسطول';

  @override
  String get docWaitingReview => 'بانتظار المراجعة';

  @override
  String get docApproved => 'مقبول';

  @override
  String get docRefused => 'مرفوض';

  @override
  String get payoutFormatChecked => 'تم التحقق من الصيغة';

  @override
  String get payoutVerified => 'موثَّق';

  @override
  String get payoutFailedVerification => 'فشل التوثيق';

  @override
  String get notifCatOrderUpdates => 'تحديثات الطلبات';

  @override
  String get notifCatChat => 'المحادثات';

  @override
  String get notifCatPromotions => 'العروض الترويجية';

  @override
  String get notifCatAccount => 'الحساب والأمان';

  @override
  String get notifChannelPush => 'إشعارات فورية';

  @override
  String get notifChannelInApp => 'داخل التطبيق';

  @override
  String get notifChannelEmail => 'البريد الإلكتروني';

  @override
  String get notifChannelSms => 'رسائل نصية';

  @override
  String get chatRoleCustomer => 'الزبون';

  @override
  String get chatRoleRider => 'السائق';

  @override
  String get crossSellBoughtTogether => 'يُشترى معاً غالباً';

  @override
  String get crossSellSameShelf => 'من الرف نفسه';

  @override
  String get crossSellYouMightAlsoLike => 'قد يعجبك أيضاً';

  @override
  String get ratingNewRider => 'جديد';

  @override
  String get custTestPayment => 'دفعة تجريبية';

  @override
  String get custPaymentDeclined => 'رُفض الدفع ولم يُقدَّم طلبك.';

  @override
  String get custPromoRemove => 'إزالة الرمز';

  @override
  String get custPromoChecking => 'جارٍ التحقق من الرمز…';

  @override
  String get promoCouldNotCheck => 'تعذّر التحقق من الرمز';

  @override
  String get etaMinShort => 'دقيقة';

  @override
  String get etaArriving => 'الوصول المتوقع';

  @override
  String get etaRemaining => 'المتبقي';

  @override
  String get custChatWithRider => 'مراسلة السائق';

  @override
  String get chatTypeMessage => 'اكتب رسالة…';

  @override
  String get chatSend => 'إرسال';

  @override
  String get chatClosed => 'أُغلقت هذه المحادثة';

  @override
  String get chatNoMessagesYet => 'لا رسائل بعد';

  @override
  String get chatCouldNotSend => 'تعذّر إرسال رسالتك';

  @override
  String get couldNotLoadChat => 'تعذّر تحميل المحادثة';

  @override
  String get custRateYourRider => 'قيّم السائق';

  @override
  String get custHowWasDelivery => 'كيف كانت تجربة التوصيل؟';

  @override
  String get custAddCommentOptional => 'أضف تعليقاً (اختياري)';

  @override
  String get custSubmitRating => 'إرسال التقييم';

  @override
  String get custThanksForRating => 'شكراً لتقييمك السائق';

  @override
  String get custAlreadyRatedDelivery => 'لقد قيّمت هذا التوصيل';

  @override
  String get custCouldNotSendRating => 'تعذّر إرسال تقييمك';

  @override
  String ratingStars(Object n) {
    return '$n نجوم';
  }

  @override
  String get searchForAPlace => 'ابحث عن مكان…';

  @override
  String get noPlacesFound => 'لم يُعثر على أماكن';

  @override
  String get couldNotSearchPlaces => 'تعذّر البحث الآن';

  @override
  String get addressPinnedOnMap => 'محدَّد على الخريطة';

  @override
  String get notifPreferences => 'تفضيلات الإشعارات';

  @override
  String get notifPrefsBlurb => 'اختر كيف نتواصل معك، موضوعاً بموضوع';

  @override
  String get notifAlwaysOn =>
      'مفعَّل دائماً — لا يمكن إيقاف رسائل الحساب والأمان';

  @override
  String get couldNotLoadPreferences => 'تعذّر تحميل تفضيلاتك';

  @override
  String get couldNotSaveThatChange => 'تعذّر حفظ هذا التغيير';

  @override
  String crossSellTogetherCount(Object count) {
    return '$count× معاً';
  }

  @override
  String riderBalanceLine(Object balance, Object available) {
    return 'الرصيد $balance · المتاح للسحب $available';
  }

  @override
  String riderEarningsBreakdown(Object earnings, Object tips) {
    return '$earnings أجرة توصيل · $tips إكراميات';
  }

  @override
  String get riderCashOutTitle => 'سحب الرصيد';

  @override
  String get riderCashOutAvailable => 'المتاح للسحب';

  @override
  String riderCashOutHeldNote(Object amount) {
    return '$amount منها نقد لا يزال بحوزتك — سلّمه ليصبح متاحاً';
  }

  @override
  String riderCashOutMinimum(Object amount) {
    return 'الحد الأدنى $amount';
  }

  @override
  String get riderCashOutManualNote =>
      'تُسلَّم الدفعات يدوياً من فريق المنصة — لا يُحوَّل شيء تلقائياً.';

  @override
  String get riderCashOutRequest => 'طلب سحب';

  @override
  String get riderCashOutAmountLabel => 'المبلغ';

  @override
  String get riderCashOutAlreadyOpen => 'هناك طلب سحب قيد المعالجة بالفعل.';

  @override
  String get riderCashOutFailed => 'تعذّر طلب السحب.';

  @override
  String riderCashOutOpenLine(Object amount) {
    return '$amount مطلوبة — بانتظار التسليم';
  }

  @override
  String get riderCashOutLastRefused => 'رُفض طلب السحب الأخير.';

  @override
  String get riderCashOutHistory => 'الطلبات الأخيرة';

  @override
  String riderTipLine(Object tip) {
    return '+$tip إكرامية';
  }

  @override
  String riderReimbursedLine(Object amount) {
    return '+$amount مستردّة';
  }

  @override
  String riderLastSeen(Object when) {
    return 'آخر ظهور $when';
  }

  @override
  String get riderDutyChangeFailed => 'تعذّر تحديث حالة الدوام.';

  @override
  String get riderDutyNotYetDeclared => 'لم تبدأ الدوام بعد.';

  @override
  String get riderEtaCaption => 'الوقت المتوقع للوصول';

  @override
  String riderEtaAway(Object distance) {
    return 'على بُعد $distance';
  }

  @override
  String riderEtaArrivingAt(Object time) {
    return 'الوصول نحو $time';
  }

  @override
  String riderKmUnit(Object km) {
    return '$km كم';
  }

  @override
  String riderMetreUnit(Object m) {
    return '$m م';
  }

  @override
  String riderEtaComputedBy(Object provider) {
    return 'التقدير من $provider';
  }

  @override
  String get riderChatTitle => 'محادثة الزبون';

  @override
  String get riderChatHint => 'اكتب رسالة…';

  @override
  String get riderChatSend => 'إرسال';

  @override
  String get riderChatClosed => 'أُغلقت هذه المحادثة.';

  @override
  String get riderChatEmpty => 'لا رسائل بعد.';

  @override
  String get riderChatCouldNotLoad => 'تعذّر تحميل المحادثة';

  @override
  String get riderChatSendFailed => 'لم تُرسَل الرسالة.';

  @override
  String get riderChatReconnecting => 'جارٍ إعادة الاتصال…';

  @override
  String get wizDocsIntro =>
      'صور واضحة أو ملفات PDF. يمكنك استبدال أي مستند حتى صدور القرار.';

  @override
  String get wizDocFileTypes => 'صور وملفات PDF';

  @override
  String get wizDocAdd => 'إضافة';

  @override
  String get wizDocReplace => 'استبدال';

  @override
  String get wizDocRemove => 'إزالة';

  @override
  String get wizDocReadyToSend => 'جاهز للإرسال';

  @override
  String get wizDocNotAddedYet => 'لم يُضف بعد';

  @override
  String get wizDocSentOnSubmit => 'تُرسَل مستنداتك عند تقديم الطلب.';

  @override
  String get wizDocTooLarge => 'حجم الملف كبير جداً';

  @override
  String get wizDocUploadFailed => 'لم يكتمل الرفع';

  @override
  String get wizDocUploading => 'جارٍ الرفع…';

  @override
  String get wizDocCouldNotLoad => 'تعذّر تحميل مستنداتك';

  @override
  String get wizDocsPendingTitle => 'مستنداتك';

  @override
  String get wizDocsPendingBlurb =>
      'يمكن استبدال أي مستند مرفوض وستتم مراجعته من جديد.';

  @override
  String get wizDocsNoneYet => 'لم يُرفع أي مستند بعد';

  @override
  String get wizCouldNotSendDocuments =>
      'تم استلام طلبك، لكن أحد المستندات لم يُرسل.';

  @override
  String get wizPayoutAccountHolder => 'اسم صاحب الحساب';

  @override
  String get wizPayoutAccountHolderHint => 'الاسم كما هو مسجَّل لدى البنك';

  @override
  String get wizPayoutIban => 'رقم الحساب الدولي (IBAN)';

  @override
  String get wizPayoutIbanHint => 'يبدأ برمز الدولة، مثل …SA';

  @override
  String get wizPayoutIbanInvalid =>
      'رقم الآيبان غير صحيح — الأرجح أن رقماً خاطئ أو رقمين متبادلان';

  @override
  String get wizPayoutIbanFormat =>
      'يبدأ رقم الآيبان بحرفين لرمز الدولة يليهما رقما تحقق';

  @override
  String get wizPayoutIbanBounds => 'يتكوّن رقم الآيبان من 15 إلى 34 خانة';

  @override
  String wizPayoutIbanLength(Object country, Object expected) {
    return 'رقم الآيبان لدولة $country يتكوّن من $expected خانة';
  }

  @override
  String get wizPayoutCouldNotSave => 'تعذّر حفظ البيانات البنكية';

  @override
  String get wizPayoutCouldNotLoad => 'تعذّر تحميل بياناتك البنكية';

  @override
  String get wizPayoutSave => 'حفظ البيانات البنكية';

  @override
  String get wizPayoutChange => 'تغيير';

  @override
  String get wizPayoutSentOnSubmit => 'تُرسَل بياناتك البنكية عند تقديم الطلب.';

  @override
  String get wizCouldNotSendPayout =>
      'تم استلام طلبك، لكن البيانات البنكية لم تُرسل.';

  @override
  String get merchPinShopLocation => 'موقع المتجر';

  @override
  String get merchPinDropHint =>
      'انقر على الخريطة لتضع الدبوس على متجرك، ثم احفظ.';

  @override
  String get merchPinWhyItMatters =>
      'يرى العملاء هذا الدبوس، ومنه تُقاس مسافة التوصيل.';

  @override
  String get merchPinNoneYet => 'لم يُحدَّد موقع بعد';

  @override
  String get merchPinSetIt => 'حدِّد الموقع';

  @override
  String get merchPinSaved => 'تم حفظ موقع المتجر';

  @override
  String get merchPinCleared => 'تمت إزالة موقع المتجر';

  @override
  String get merchMapUnavailable => 'تعذّر تحميل الخريطة';

  @override
  String merchUpOnPrevious(Object percent, Object days) {
    return 'أعلى بنسبة $percent% عن الـ$days يوماً السابقة';
  }

  @override
  String merchDownOnPrevious(Object percent, Object days) {
    return 'أقل بنسبة $percent% عن الـ$days يوماً السابقة';
  }

  @override
  String merchSameAsPrevious(Object days) {
    return 'مثل الـ$days يوماً السابقة';
  }

  @override
  String merchNonePrevious(Object days) {
    return 'لا شيء في الـ$days يوماً السابقة';
  }

  @override
  String get merchNothingEitherPeriod => 'لا شيء في الفترتين';

  @override
  String get merchAnalyticsBlurb =>
      'كل يوم في الفترة، مقسّماً حسب سرعة التوصيل التي طلبها العميل.';

  @override
  String get merchTierSplit => 'حسب سرعة التوصيل';

  @override
  String get merchOrderValue => 'قيمة الطلبات';

  @override
  String get merchOrderValueNote =>
      'إجمالي ما دفعه العملاء، شاملاً التوصيل وأي رسم سرعة إضافي — وليس مستحقّاتك.';

  @override
  String get deliveryTierStandard => 'عادي';

  @override
  String get deliveryTierExpress => 'سريع';

  @override
  String get custPinYourDoor => 'حدّد موقع بابك';

  @override
  String get custSetHere => 'حدّد هنا';

  @override
  String get locMyLocation => 'موقعي';

  @override
  String get locServicesOff => 'خدمة الموقع مطفأة على هذا الهاتف.';

  @override
  String get locTurnOn => 'تشغيل';

  @override
  String get locPermissionNeeded =>
      'اسمح بالوصول إلى الموقع ليتوجّه إليك على الخريطة.';

  @override
  String get locOpenSettings => 'افتح الإعدادات';

  @override
  String get locNoFix => 'تعذّر تحديد موقعك. جرّب مجدداً في مكان مكشوف.';

  @override
  String get custNamingThisPlace => 'جارٍ التعرّف على هذا المكان…';

  @override
  String get custMapUnavailable =>
      'تعذّر تحميل الخريطة. سنعتمد على العنوان الذي تكتبه.';

  @override
  String get custYourAddress => 'عنوانك';

  @override
  String get custTheRider => 'السائق';

  @override
  String get custDeliverySpeed => 'سرعة التوصيل';

  @override
  String get custExpressSurchargeApplies => 'تُضاف رسوم إضافية';

  @override
  String get custExpressNote =>
      'التوصيل السريع بتكلفة إضافية. تحدّد المنصّة قيمتها وتظهر في الفاتورة كبند مستقل. وعرض التوصيل المجاني لا يشملها.';

  @override
  String get authResetYourPasscode => 'إعادة تعيين رمز الدخول';

  @override
  String get authChangeYourPasscode => 'تغيير رمز الدخول';

  @override
  String get authResetAskForAddress =>
      'أدخل البريد الإلكتروني المرتبط بحسابك. إذا كان له حساب، فسيصله رمز من ستة أرقام.';

  @override
  String get authResetToYourAddress =>
      'سيصل رمز من ستة أرقام إلى البريد الإلكتروني المسجّل في حسابك.';

  @override
  String authResetCodeMaybeSent(Object destination) {
    return 'إذا كان لدى $destination حساب، فإن رمزًا من ٦ أرقام في طريقه إليه. تنتهي صلاحيته خلال ١٠ دقائق ويُستخدم مرة واحدة.';
  }

  @override
  String get authSetNewPasscode => 'تعيين رمز الدخول';

  @override
  String get authPasscodeChanged => 'تم تغيير رمز الدخول';

  @override
  String get authPasscodeChangedSignIn =>
      'سجّل الدخول باستخدام رمزك الجديد المكوّن من ستة أرقام.';

  @override
  String get authPasscodeChangedSignedIn =>
      'استخدم رمزك الجديد المكوّن من ستة أرقام في المرة القادمة التي تسجّل فيها الدخول.';

  @override
  String get custProfileFieldsFixed =>
      'تم تحديد اسمك وبريدك الإلكتروني عند إنشاء الحساب، ولا يمكن تغييرهما من التطبيق حتى الآن.';

  @override
  String get custNoEmailOnAccount =>
      'لا يوجد بريد إلكتروني مرتبط بهذا الحساب، لذا لا يوجد مكان يُرسَل إليه الرمز.';

  @override
  String get custCouldNotOpenThat =>
      'لا يوجد تطبيق على هذا الهاتف يمكنه فتح ذلك.';

  @override
  String get custHelpIntro =>
      'إجابات عن أكثر ما يسأل عنه الناس، وطرق التواصل مع شخص حقيقي إذا لم تجد إجابتك هنا.';

  @override
  String get custHelpTalkToUs => 'تواصل معنا';

  @override
  String get custChatOnWhatsApp => 'المحادثة عبر واتساب';

  @override
  String get custEmailSupport => 'مراسلة الدعم بالبريد';

  @override
  String get custHelpNoChannelsYet =>
      'لم يتم إعداد قناة دعم في هذه النسخة بعد. ولا يزال بإمكانك مراسلة السائق من صفحة الطلب بعد إسناده.';

  @override
  String get custHelpOrdering => 'الطلب';

  @override
  String get custHelpDelivery => 'التوصيل';

  @override
  String get custHelpPayments => 'الدفع';

  @override
  String get custHelpAccount => 'حسابك';

  @override
  String get custHelpApplying => 'البيع والتوصيل';

  @override
  String get custFaqOneShopQ => 'لماذا تقتصر السلة على متجر واحد؟';

  @override
  String get custFaqOneShopA =>
      'الطلب الواحد يذهب إلى متجر واحد ويحمله سائق واحد. متجران يعنيان عمليتَي استلام ورسمين ورحلتين، لذلك تطلب منك السلة إنهاء أحدهما قبل البدء بالآخر.';

  @override
  String get custFaqMinimumQ => 'ما هو الحد الأدنى للطلب؟';

  @override
  String get custFaqMinimumA =>
      'بعض المتاجر لا ترسل سائقًا لطلب أقل من مبلغ معيّن. تعرض السلة الحد الأدنى للمتجر والمبلغ المتبقّي بالضبط، ويبقى إتمام الطلب مغلقًا حتى يتحقّق.';

  @override
  String get custFaqChangeOrderQ => 'هل يمكنني تعديل الطلب أو إلغاؤه؟';

  @override
  String get custFaqChangeOrderA =>
      'لا يمكن تعديل الطلب بعد إرساله. تعرض صفحة الطلب ما يمكنك فعله به، ويختفي خيار الإلغاء من القائمة بمجرد أن يبدأ المتجر بالتحضير. وبعد إسناد سائق يمكنك مراسلته من صفحة الطلب.';

  @override
  String get custFaqTiersQ => 'ما الفرق بين العادي والسريع؟';

  @override
  String get custFaqTiersA =>
      'التوصيل السريع يجعل الطلب ذا أولوية ويضيف رسومًا فوق رسوم التوصيل. تحدّد المنصّة هذه القيمة وليس المتجر، وتظهر في الفاتورة كبند مستقل. وعرض التوصيل المجاني يغطي رسوم التوصيل فقط، أما رسوم السرعة فتبقى مستحقّة.';

  @override
  String get custFaqWhereIsRiderQ => 'أين السائق؟';

  @override
  String get custFaqWhereIsRiderA =>
      'تعرض صفحة الطلب مواقع السائق المسجّلة على الخريطة منذ لحظة استلامه طلبك. ويأتي وقت الوصول من خدمة التتبّع؛ وعندما لا يتوفّر لديها موقع حديث تقول ذلك بدل عرض تخمين.';

  @override
  String get custFaqDeliveryFeeQ => 'كيف تُحتسب رسوم التوصيل؟';

  @override
  String get custFaqDeliveryFeeA =>
      'بحسب المنطقة التي يُوصَّل إليها، ولهذا يحمل العنوان المحفوظ منطقة. وقد يلغيها عرض ترويجي، وعندها تذكر السلة اسم العرض بدل عرض صفر فقط.';

  @override
  String get custFaqAddressPinQ => 'لماذا أضع دبوسًا على الخريطة؟';

  @override
  String get custFaqAddressPinA =>
      'السطر المكتوب يوصل السائق إلى الشارع، والدبوس يوصله إلى الباب، وهو النقطة التي يُحتسب عليها وقت الوصول. وبدونه يصل طلبك أيضًا، لكن لا توجد نقطة على الخريطة يُقدَّر منها الوقت.';

  @override
  String get custFaqPayMethodsQ => 'ما وسائل الدفع التي تعمل فعليًا؟';

  @override
  String get custFaqPayMethodsA =>
      'الدفع نقدًا عند الاستلام هو الوسيلة الوحيدة في هذه النسخة التي تحرّك أموالًا حقيقية. أما البطاقة والمحفظة فموصولتان بمزوّد دفع تجريبي وتظهران عند الدفع بعلامة «دفع تجريبي»: اختيار إحداهما يتم عبر ذلك المزوّد ولا يُخصم منك شيء.';

  @override
  String get custFaqPromoQ => 'كيف تعمل رموز الخصم؟';

  @override
  String get custFaqPromoA =>
      'اكتب الرمز في السلة ليُفحَص مقابل محتوياتها في تلك اللحظة، فقد يبدأ تطبيقه فور تجاوزك حدّه الأدنى. أما المبلغ المحتسَب فعليًا فيعيد الخادم حسابه عند إرسال الطلب، ويظهر في تأكيد الطلب.';

  @override
  String get custFaqRefundQ => 'كيف أسترد مبلغًا؟';

  @override
  String get custFaqRefundA =>
      'لا يوجد زر لاسترداد المبلغ في التطبيق. تُسوّى الطلبات النقدية عند الباب، لذا تُعالَج أي مشكلة معنا مباشرة — راسلنا عبر واتساب أو البريد مع رقم الطلب وما حدث.';

  @override
  String get custFaqPasscodeQ => 'نسيت رمز الدخول.';

  @override
  String get custFaqPasscodeA =>
      'اضغط «نسيت كلمة المرور؟» في شاشة تسجيل الدخول. يُرسَل رمز من ستة أرقام إلى بريد الحساب، ويبقى صالحًا عشر دقائق ويُستخدم مرة واحدة. ومن داخل التطبيق ستجد الخطوات نفسها تحت «تعديل» في هذه الشاشة.';

  @override
  String get custFaqProfileQ => 'هل يمكنني تغيير اسمي أو بريدي الإلكتروني؟';

  @override
  String get custFaqProfileA =>
      'ليس من التطبيق حتى الآن. فقد تم تحديدهما عند إنشاء الحساب؛ ورمز الدخول هو الشيء الوحيد في الحساب الذي يمكنك تغييره بنفسك.';

  @override
  String get custFaqApplyQ => 'كيف أبيع عبر YouDrop أو أعمل في التوصيل؟';

  @override
  String get custFaqApplyA =>
      'من شاشة الترحيب قبل تسجيل الدخول: اختر متجرًا أو سائقًا واملأ الطلب. سيُطلب منك بيانات التواصل والمستندات وتفاصيل التحويل، وستحصل على حساب في النهاية لتسجّل الدخول وتتابع طلبك.';

  @override
  String get custFaqApplyWaitQ => 'كم يستغرق النظر في الطلب؟';

  @override
  String get custFaqApplyWaitA =>
      'يقرأه شخص حقيقي، لذا لا توجد مدة ثابتة. تعرض شاشة طلبك المرحلة التي وصل إليها وما إذا أُعيد أي مستند للتصحيح — تلك الشاشة هي الحالة، ولا يُتخذ أي قرار تلقائيًا.';

  @override
  String deliveryTierExpressSurcharge(Object amount) {
    return 'سريع +$amount';
  }

  @override
  String get riderTierExpress => 'سريع';

  @override
  String get riderCompletionRate => 'نسبة الإتمام';

  @override
  String riderHoursValue(Object hours) {
    return '$hours س';
  }

  @override
  String riderPerformanceLine(Object delivered, Object claimed, Object days) {
    return 'أُنجزت $delivered من $claimed مهمة مقبولة خلال $days يوماً';
  }

  @override
  String riderPerformanceDropped(Object count) {
    return ' · $count تُركت بعد القبول';
  }

  @override
  String ratingWithCount(Object average, Object ratings) {
    return '$average · $ratings تقييماً';
  }

  @override
  String get riderMapYouAreHere => 'أنت';

  @override
  String get riderMapNoFixYet => 'بانتظار أول إشارة GPS';

  @override
  String get riderMapUnavailable => 'الخريطة غير متاحة';

  @override
  String get riderNavigateFailed => 'تعذّر فتح تطبيق خرائط.';

  @override
  String get riderRegionAllAreas => 'كل المناطق';

  @override
  String get riderHelpTitle => 'المساعدة والدعم';

  @override
  String get riderHelpConversations => 'محادثاتك';

  @override
  String get riderHelpNoConversations =>
      'تُفتح محادثة مع الزبون في كل مهمة تُسند إليك.';

  @override
  String get riderHelpCouldNotLoad => 'تعذّر تحميل محادثاتك';

  @override
  String riderHelpOrderThread(Object ref) {
    return 'الطلب $ref';
  }

  @override
  String get riderHelpThreadClosed => 'مغلقة';

  @override
  String get riderHelpHowItWorks => 'كيف يعمل هذا';

  @override
  String get riderHelpDuty =>
      'لا تصلك مهام إلا وأنت على رأس العمل وهاتفك يرسل موقعه.';

  @override
  String get riderHelpClaim =>
      'تصبح المهمة لك فور قبولها. وإن سبقك إليها غيرك، فسيخبرك اللوح بذلك.';

  @override
  String get riderHelpCashOut =>
      'يُطلب السحب من تبويب الأرباح ويُسلَّم يدوياً من فريق المنصة.';

  @override
  String get riderHelpExpress =>
      'المهمة السريعة يدفع فيها الزبون مقابل السرعة. والعلاوة للمنصة وليست جزءاً من أجرتك.';

  @override
  String get riderDocumentsTitle => 'المستندات والرخص';

  @override
  String get riderDocumentsCouldNotLoad => 'تعذّر تحميل مستنداتك';

  @override
  String get riderPayoutCouldNotLoad => 'تعذّر تحميل بياناتك المصرفية';

  @override
  String get authPinYourArea =>
      'اضغط على الخريطة لتحديد المنطقة التي ستعمل فيها';

  @override
  String authPinnedAt(Object lat, Object lng) {
    return 'مثبّت عند $lat، $lng';
  }

  @override
  String get authPinClear => 'إزالة الدبوس';

  @override
  String get authMapUnavailable => 'الخريطة غير متاحة';

  @override
  String get riderStatementTitle => 'التسوية';

  @override
  String get riderStatementRowSubtitle => 'النقد الذي بحوزتك، مقابل ما كسبته';

  @override
  String get riderStatementPeriodThisMonth => 'هذا الشهر';

  @override
  String get riderStatementPeriodLastMonth => 'الشهر الماضي';

  @override
  String riderStatementRangeLine(Object from, Object to) {
    return '$from – $to';
  }

  @override
  String riderStatementGeneratedAt(Object when) {
    return 'احتُسب $when';
  }

  @override
  String get riderStatementCouldNotLoad => 'تعذّر تحميل كشف حسابك';

  @override
  String get riderStatementNothingYet => 'لم تتحرك أي مبالغ في هذه الفترة.';

  @override
  String get riderStatementSummary => 'كيف يُحتسب';

  @override
  String get riderStatementOrders => 'طلبات هذه الفترة';

  @override
  String riderStatementCollectedLine(Object amount) {
    return 'حصّلت $amount عند الباب';
  }

  @override
  String get riderStatementYouOwe => 'أنت مدين للمنصة';

  @override
  String get riderStatementOwedToYou => 'المنصة مدينة لك';

  @override
  String get riderStatementSettled => 'لا شيء معلّق في الاتجاهين';

  @override
  String get riderStatementDirectionUnclear => 'تعذّرت قراءة اتجاه هذا الرصيد';

  @override
  String get riderStatementDebtNote =>
      'هذا أمر طبيعي. النقد الذي تحصّله عند الباب يخصّ المنصة حتى تسلّمه — وهو ليس خصماً من أجرك.';

  @override
  String get riderStatementCreditNote => 'هذا مالك، ولم يصلك بعد.';

  @override
  String get riderStatementSettledNote => 'جرت تسوية كل ما حصّلته.';

  @override
  String get riderStatementUnclearNote =>
      'تعذّر على التطبيق تحديد اتجاه هذا الرصيد. راجع المنصة قبل التصرّف بناءً عليه.';

  @override
  String get navPos => 'نقطة البيع';

  @override
  String get navInventory => 'المخزون';

  @override
  String get navReports => 'التقارير';

  @override
  String get navStaff => 'الفريق';

  @override
  String get dashSwitchToPos => 'التبديل إلى وضع نقطة البيع';

  @override
  String get dashWalkInSalesToday => 'مبيعات المحل اليوم';

  @override
  String get dashCashPayouts => 'المقبوض نقداً';

  @override
  String get dashCardPayouts => 'المقبوض بالبطاقة';

  @override
  String get dashLowStockAlerts => 'تنبيهات نقص المخزون';

  @override
  String get dashQuickActions => 'إجراءات سريعة';

  @override
  String get dashNewSale => 'بيع جديد';

  @override
  String get dashAddProduct => 'إضافة منتج';

  @override
  String get dashStockCount => 'جرد المخزون';

  @override
  String get dashViewReports => 'عرض التقارير';

  @override
  String get posTitle => 'نقطة البيع';

  @override
  String get posSearchProducts => 'ابحث عن منتج أو رمز أو باركود';

  @override
  String get posScanBarcode => 'مسح الباركود';

  @override
  String get posNoProducts => 'لا منتجات للبيع بعد';

  @override
  String get posNoProductsHint => 'أضف منتجاً إلى كتالوجك ليظهر هنا.';

  @override
  String get posCouldNotLoadCatalogue => 'تعذّر تحميل الكتالوج';

  @override
  String get posCart => 'البيع الحالي';

  @override
  String get posCartEmpty => 'لم يُسجَّل أي صنف بعد';

  @override
  String get posCartEmptyHint => 'اضغط على منتج لبدء عملية البيع.';

  @override
  String posLinesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صنف',
      many: '$count صنفاً',
      few: '$count أصناف',
      two: 'صنفان',
      one: 'صنف واحد',
      zero: 'لا أصناف',
    );
    return '$_temp0';
  }

  @override
  String get posSubtotal => 'المجموع الفرعي';

  @override
  String get posDiscount => 'الخصم';

  @override
  String get posTax => 'الضريبة';

  @override
  String get posTotal => 'الإجمالي';

  @override
  String get posPaid => 'المدفوع';

  @override
  String get posOutstanding => 'المتبقي';

  @override
  String get posRefundedAmount => 'المُعاد';

  @override
  String posUsd(String amount) {
    return '$amount \$';
  }

  @override
  String posLbp(String amount) {
    return '$amount ل.ل.';
  }

  @override
  String posRate(String rate) {
    return '1 دولار = $rate ل.ل.';
  }

  @override
  String get posCharge => 'تحصيل';

  @override
  String get posClearSale => 'إلغاء البيع';

  @override
  String get posQuantity => 'الكمية';

  @override
  String get posRemoveLine => 'إزالة';

  @override
  String get posAddOpenItem => 'إضافة صنف مفتوح';

  @override
  String get posOpenItem => 'صنف مفتوح';

  @override
  String get posOpenItemName => 'ما هو الصنف؟';

  @override
  String get posOpenItemPrice => 'السعر';

  @override
  String get posDiscountTitle => 'تطبيق خصم';

  @override
  String get posDiscountAmount => 'قيمة الخصم';

  @override
  String get posDiscountNote => 'السبب (اختياري)';

  @override
  String get posApplyDiscount => 'تطبيق الخصم';

  @override
  String get posDiscountTooLarge =>
      'هذا الخصم يتجاوز صلاحيتك. اطلب موافقة المسؤول.';

  @override
  String get posCouldNotLoadSale => 'تعذّر تحميل هذه العملية';

  @override
  String get posTerminalUnavailable => 'نقطة البيع غير متاحة بعد.';

  @override
  String get posCheckout => 'الدفع';

  @override
  String get posTenderMethod => 'كيف سيدفع الزبون؟';

  @override
  String get posCashUsd => 'نقداً (دولار)';

  @override
  String get posCashLbp => 'نقداً (ليرة)';

  @override
  String get posCard => 'بطاقة';

  @override
  String get posWallet => 'محفظة YouDrop';

  @override
  String get posWalletComingSoon => 'قريباً';

  @override
  String get posAmountTendered => 'المبلغ المستلم';

  @override
  String get posCardReference => 'رقم المرجع (اختياري)';

  @override
  String get posChangeIn => 'الفكة بعملة';

  @override
  String get posChangeDue => 'الفكة المستحقة';

  @override
  String get posChangePreview => 'معاينة — الصندوق يثبّت الرقم النهائي.';

  @override
  String get posRoundingLbp => 'مقرَّب إلى أقرب ورقة نقدية';

  @override
  String get posSplitPayment => 'تقسيم الدفع';

  @override
  String get posAddTender => 'إضافة دفعة أخرى';

  @override
  String posRemainingAmount(String amount) {
    return 'المتبقي $amount';
  }

  @override
  String get posCompleteSale => 'إتمام البيع';

  @override
  String get posSaleCompleted => 'تم إتمام البيع';

  @override
  String get posTendersShort => 'الدفعات لا تغطي الإجمالي بعد.';

  @override
  String get posReceipt => 'الإيصال';

  @override
  String get posReceiptChannel => 'إرسال الإيصال';

  @override
  String get posReceiptPrint => 'طباعة';

  @override
  String get posReceiptSms => 'رسالة نصية';

  @override
  String get posReceiptWhatsapp => 'واتساب';

  @override
  String get posReceiptEmail => 'بريد إلكتروني';

  @override
  String get posReceiptNone => 'بدون إيصال';

  @override
  String get posReceiptContact => 'إلى أين نرسله';

  @override
  String get posReceiptSent => 'تم إرسال الإيصال';

  @override
  String posReceiptNo(String label) {
    return 'إيصال $label';
  }

  @override
  String get posPrintReceipt => 'طباعة الإيصال';

  @override
  String get posShareReceipt => 'مشاركة الإيصال';

  @override
  String get posNewSale => 'بيع جديد';

  @override
  String get posCashier => 'أمين الصندوق';

  @override
  String get posThankYou => 'شكراً لك';

  @override
  String get posShift => 'الوردية';

  @override
  String posShiftActive(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'الوردية مفتوحة · $count عملية',
      many: 'الوردية مفتوحة · $count عملية',
      few: 'الوردية مفتوحة · $count عمليات',
      two: 'الوردية مفتوحة · عمليتان',
      one: 'الوردية مفتوحة · عملية واحدة',
      zero: 'الوردية مفتوحة',
    );
    return '$_temp0';
  }

  @override
  String get posOpenShift => 'فتح وردية';

  @override
  String get posCloseShift => 'إغلاق الوردية';

  @override
  String get posOpeningFloat => 'النقد في الدرج (دولار)';

  @override
  String get posOpeningFloatLbp => 'النقد في الدرج (ليرة)';

  @override
  String get posCountedCash => 'المعدود (دولار)';

  @override
  String get posCountedCashLbp => 'المعدود (ليرة)';

  @override
  String get posExpected => 'المتوقع';

  @override
  String get posCounted => 'المعدود';

  @override
  String get posVariance => 'الفرق';

  @override
  String get posShiftClosed => 'أُغلقت الوردية';

  @override
  String get posShiftSummary => 'ملخص الوردية';

  @override
  String get posNoShift => 'لا توجد وردية مفتوحة';

  @override
  String get posNoShiftHint => 'افتح وردية قبل بدء البيع.';

  @override
  String get posRegister => 'الصندوق';

  @override
  String get posRegisters => 'الصناديق';

  @override
  String get posAddRegister => 'إضافة صندوق';

  @override
  String get posRegisterName => 'اسم الصندوق';

  @override
  String get posSelectRegister => 'اختر صندوقاً';

  @override
  String get posSalesCount => 'المبيعات';

  @override
  String get posByMethod => 'حسب طريقة الدفع';

  @override
  String get posStatusOpen => 'مفتوحة';

  @override
  String get posStatusCompleted => 'مكتملة';

  @override
  String get posStatusVoided => 'ملغاة';

  @override
  String get posStatusPartiallyRefunded => 'مُعادة جزئياً';

  @override
  String get posStatusRefunded => 'مُعادة';

  @override
  String get posActionComplete => 'تحصيل';

  @override
  String get posActionVoid => 'إلغاء';

  @override
  String get posActionRefund => 'إرجاع';

  @override
  String get posActionReprint => 'إعادة طباعة الإيصال';

  @override
  String get posVoidSale => 'إلغاء هذه العملية';

  @override
  String get posVoidReason => 'سبب الإلغاء';

  @override
  String get posVoidConfirm => 'تأكيد الإلغاء';

  @override
  String get posVoided => 'أُلغيت العملية';

  @override
  String get posRefundTitle => 'إرجاع أصناف';

  @override
  String get posRefundQty => 'كم صنفاً يُعاد؟';

  @override
  String get posRefundMethod => 'طريقة الإرجاع';

  @override
  String get posRefundRestock => 'إعادة الأصناف إلى الرف';

  @override
  String get posRefundReason => 'السبب (اختياري)';

  @override
  String get posRefundConfirm => 'تنفيذ الإرجاع';

  @override
  String get posRefundDone => 'تم الإرجاع';

  @override
  String get invTitle => 'المخزون';

  @override
  String get invSearch => 'ابحث بالاسم أو الرمز أو الباركود';

  @override
  String get invFilterAll => 'الكل';

  @override
  String get invFilterLowStock => 'مخزون منخفض';

  @override
  String get invFilterOutOfStock => 'نفد المخزون';

  @override
  String get invFilterActive => 'معروضة';

  @override
  String get invFilterHidden => 'مخفية';

  @override
  String get invOnHand => 'المتوفر بالمستودع';

  @override
  String get invReserved => 'محجوز لطلبات';

  @override
  String get invAvailable => 'المتاح للبيع';

  @override
  String get invThreshold => 'حد التنبيه';

  @override
  String invSku(String sku) {
    return 'الرمز $sku';
  }

  @override
  String get invBarcode => 'الباركود';

  @override
  String get invNotTracked => 'غير متتبَّع';

  @override
  String get invTrackStock => 'تتبّع المخزون';

  @override
  String get invTrackStockHint => 'يخفي YouDrop الصنف عند نفاده.';

  @override
  String get invInitialStock => 'الكمية الحالية';

  @override
  String get invStatusOk => 'متوفر';

  @override
  String get invStatusWarning => 'منخفض';

  @override
  String get invStatusCritical => 'حرِج';

  @override
  String get invStatusOut => 'نفد';

  @override
  String get invEmpty => 'لا شيء في المخزون بعد';

  @override
  String get invEmptyHint => 'أضف منتجات إلى كتالوجك لتظهر هنا.';

  @override
  String get invCouldNotLoad => 'تعذّر تحميل المخزون';

  @override
  String get invSyncing => 'يجري إحضار كتالوجك…';

  @override
  String invSynced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أُضيف $count منتج',
      many: 'أُضيف $count منتجاً',
      few: 'أُضيفت $count منتجات',
      two: 'أُضيف منتجان',
      one: 'أُضيف منتج واحد',
      zero: 'لا شيء لإضافته',
    );
    return '$_temp0';
  }

  @override
  String get invProducts => 'المنتجات';

  @override
  String get invCategories => 'الأقسام';

  @override
  String get invAlerts => 'التنبيهات';

  @override
  String get invAdjust => 'تعديل المخزون';

  @override
  String get invAdjustAdd => 'إضافة';

  @override
  String get invAdjustRemove => 'خصم';

  @override
  String get invAdjustSetTo => 'ضبط على';

  @override
  String get invAdjustQuantity => 'كم الكمية؟';

  @override
  String get invAdjustReason => 'السبب';

  @override
  String get invAdjustNote => 'ملاحظة (اختياري)';

  @override
  String get invAdjustSave => 'حفظ التعديل';

  @override
  String get invAdjusted => 'تم تحديث المخزون';

  @override
  String get invReasonReceived => 'بضاعة واردة';

  @override
  String get invReasonDamaged => 'تالف';

  @override
  String get invReasonExpired => 'منتهي الصلاحية';

  @override
  String get invReasonTheft => 'سرقة أو فقدان';

  @override
  String get invReasonCorrection => 'تصحيح';

  @override
  String get invReasonOther => 'أخرى';

  @override
  String get invMovements => 'سجل الحركة';

  @override
  String get invNoMovements => 'لا حركة بعد';

  @override
  String get invKindReceipt => 'استلام';

  @override
  String get invKindAdjustment => 'تعديل';

  @override
  String get invKindCount => 'جرد';

  @override
  String get invKindSale => 'بيع';

  @override
  String get invKindReturn => 'إرجاع';

  @override
  String get invKindOrderReserve => 'حجز لطلب';

  @override
  String get invKindOrderRelease => 'فك الحجز';

  @override
  String get invKindOrderFulfil => 'تسليم طلب';

  @override
  String get invSettings => 'إعدادات المخزون';

  @override
  String get invAlertsEnabled => 'تنبيهات نقص المخزون';

  @override
  String get invWhatsappAlerts => 'إرسال التنبيهات عبر واتساب';

  @override
  String get invAlertsTitle => 'تنبيهات المخزون';

  @override
  String invAlertsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صنف يحتاج تعبئة',
      many: '$count صنفاً يحتاج تعبئة',
      few: '$count أصناف تحتاج تعبئة',
      two: 'صنفان يحتاجان تعبئة',
      one: 'صنف واحد يحتاج تعبئة',
      zero: 'لا شيء يحتاج تعبئة',
    );
    return '$_temp0';
  }

  @override
  String get invAlertsEmpty => 'كل الرفوف ممتلئة';

  @override
  String get invAlertsEmptyHint => 'سننبّهك هنا عندما يقارب صنف على النفاد.';

  @override
  String get invAlertsCouldNotLoad => 'تعذّر تحميل تنبيهات المخزون';

  @override
  String invVelocity(String perDay) {
    return 'يُباع نحو $perDay يومياً';
  }

  @override
  String invHoursOfCover(String hours) {
    return 'يكفي نحو $hours ساعة';
  }

  @override
  String invLastSold(Object when) {
    return 'آخر بيع $when';
  }

  @override
  String get invNoVelocityYet => 'لا توجد مبيعات كافية للتقدير';

  @override
  String get invRestock => 'تعبئة';

  @override
  String get invCountTitle => 'جرد المخزون';

  @override
  String get invCountNew => 'بدء جرد';

  @override
  String get invCountName => 'اسم الجرد';

  @override
  String get invCountNameHint => 'جرد رفوف الجمعة';

  @override
  String get invCountScope => 'ماذا ستجرد؟';

  @override
  String get invCountAllProducts => 'كل المنتجات';

  @override
  String get invCountByCategory => 'قسم واحد';

  @override
  String get invCountStart => 'ابدأ الجرد';

  @override
  String invCountProgress(int count, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'جُرد $count صنف من $total',
      many: 'جُرد $count صنفاً من $total',
      few: 'جُردت $count أصناف من $total',
      two: 'جُرد صنفان من $total',
      one: 'جُرد صنف واحد من $total',
      zero: 'لم يُجرد شيء من $total',
    );
    return '$_temp0';
  }

  @override
  String get invCountSystem => 'حسب النظام';

  @override
  String get invCountCounted => 'ما عددته';

  @override
  String get invCountVariance => 'الفرق';

  @override
  String get invCountSubmit => 'اعتماد الجرد';

  @override
  String get invCountCancelCount => 'إلغاء الجرد';

  @override
  String get invCountSubmitted => 'طُبِّق الجرد على المخزون';

  @override
  String get invCountCancelled => 'أُلغي الجرد';

  @override
  String get invCountDiscrepancies => 'فروقات مرصودة';

  @override
  String get invCountNoDiscrepancies => 'كل شيء مطابق';

  @override
  String get invCountLeaveWarning => 'مغادرة الجرد؟';

  @override
  String get invCountLeaveWarningBody => 'ما جردته محفوظ، ويبقى الجرد مفتوحاً.';

  @override
  String get invCountKeepCounting => 'متابعة الجرد';

  @override
  String get invCountDiscard => 'مغادرة';

  @override
  String get invCountEmpty => 'لا عمليات جرد بعد';

  @override
  String get invCountOpenExists => 'هناك جرد مفتوح. أنهِه أولاً.';

  @override
  String get invCountStatusOpen => 'قيد التنفيذ';

  @override
  String get invCountStatusSubmitted => 'معتمد';

  @override
  String get invCountStatusCancelled => 'ملغى';

  @override
  String get catTitle => 'الأقسام';

  @override
  String get catSubtitle => 'كيف يُرتَّب متجرك أمام الزبائن';

  @override
  String get catAdd => 'إضافة قسم';

  @override
  String get catName => 'اسم القسم';

  @override
  String get catNameHint => 'المشروبات';

  @override
  String get catParent => 'يندرج تحت';

  @override
  String get catNoParent => 'المستوى الأعلى';

  @override
  String get catDragToReorder =>
      'اسحب الصفوف لتغيير ترتيب العرض في تطبيق YouDrop.';

  @override
  String catProductsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count منتج',
      many: '$count منتجاً',
      few: '$count منتجات',
      two: 'منتجان',
      one: 'منتج واحد',
      zero: 'لا منتجات',
    );
    return '$_temp0';
  }

  @override
  String get catRename => 'إعادة تسمية';

  @override
  String get catDelete => 'حذف القسم';

  @override
  String get catDeleteConfirm => 'حذف هذا القسم؟ ستبقى منتجاته في كتالوجك.';

  @override
  String catCannotDeleteNonEmpty(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ما زال هذا القسم يضم $count منتج',
      many: 'ما زال هذا القسم يضم $count منتجاً',
      few: 'ما زال هذا القسم يضم $count منتجات',
      two: 'ما زال هذا القسم يضم منتجين',
      one: 'ما زال هذا القسم يضم منتجاً واحداً',
    );
    return '$_temp0';
  }

  @override
  String get catEmpty => 'لا أقسام بعد';

  @override
  String get catEmptyHint => 'تجمع الأقسام منتجاتك في صفحة المتجر.';

  @override
  String get catCouldNotLoad => 'تعذّر تحميل الأقسام';

  @override
  String get catOrderSaved => 'حُفظ الترتيب';

  @override
  String get catOrderFailed => 'تعذّر حفظ الترتيب';

  @override
  String get catImage => 'صورة القسم';

  @override
  String get catChangeImage => 'تغيير الصورة';

  @override
  String get catYourSections => 'أقسامك';

  @override
  String get catPlatformCategories => 'تصنيفات YouDrop';

  @override
  String get staffTitle => 'الفريق';

  @override
  String get staffSubtitle => 'من يعمل هنا وما الذي يمكنه فعله';

  @override
  String get staffRoleOwner => 'المالك';

  @override
  String get staffRoleManager => 'مدير';

  @override
  String get staffRoleCashier => 'أمين صندوق';

  @override
  String get staffRoleStockkeeper => 'أمين مستودع';

  @override
  String get staffPermPosSales => 'البيع على الصندوق';

  @override
  String get staffPermPosSalesDesc => 'تسجيل مبيعات المحل وقبض المبالغ.';

  @override
  String get staffPermPosRefundsVoids => 'الإرجاع والإلغاء';

  @override
  String get staffPermPosRefundsVoidsDesc =>
      'إعادة الأموال وإلغاء عملية بيع ومنح خصم يتجاوز الحد.';

  @override
  String get staffPermModifyInventoryPricing => 'المنتجات والمخزون';

  @override
  String get staffPermModifyInventoryPricingDesc =>
      'تعديل المنتجات والأسعار وكميات المخزون.';

  @override
  String get staffPermManageOrders => 'طلبات التوصيل';

  @override
  String get staffPermManageOrdersDesc =>
      'قبول طلبات YouDrop ورفضها ومتابعتها.';

  @override
  String get staffPermViewReports => 'التقارير';

  @override
  String get staffPermViewReportsDesc =>
      'الاطلاع على أرقام المبيعات وأموال اللوحة.';

  @override
  String get staffPermAccessSettings => 'إعدادات المتجر';

  @override
  String get staffPermAccessSettingsDesc =>
      'تغيير ساعات العمل ومناطق التوصيل وملف المتجر.';

  @override
  String get staffPermManageStaff => 'الفريق';

  @override
  String get staffPermManageStaffDesc =>
      'إضافة الأعضاء وإزالتهم وتحديد صلاحياتهم.';

  @override
  String get staffStatusActive => 'نشط';

  @override
  String get staffStatusInactive => 'موقوف';

  @override
  String get staffOnShift => 'على الوردية';

  @override
  String get staffOffShift => 'خارج الوردية';

  @override
  String staffLastSeen(Object when) {
    return 'آخر ظهور $when';
  }

  @override
  String staffShiftMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'على الوردية منذ $count دقيقة',
      many: 'على الوردية منذ $count دقيقة',
      few: 'على الوردية منذ $count دقائق',
      two: 'على الوردية منذ دقيقتين',
      one: 'على الوردية منذ دقيقة',
      zero: 'بدأ الوردية للتو',
    );
    return '$_temp0';
  }

  @override
  String get staffInvite => 'دعوة شخص';

  @override
  String get staffInviteRole => 'الدور';

  @override
  String get staffInviteName => 'الاسم';

  @override
  String get staffInviteEmail => 'البريد الإلكتروني (اختياري)';

  @override
  String get staffInvitePhone => 'الهاتف (اختياري)';

  @override
  String get staffInviteCreate => 'إنشاء رمز دعوة';

  @override
  String get staffInviteCode => 'رمز الدعوة';

  @override
  String get staffInviteCodeHint =>
      'يسجّل الشخص دخوله إلى YouDrop ويدخل هذا الرمز. أنت لا تضع كلمة مروره.';

  @override
  String get staffInviteShare => 'مشاركة الرمز';

  @override
  String get staffInviteCopied => 'نُسخ الرمز';

  @override
  String staffInviteExpires(Object when) {
    return 'ينتهي $when';
  }

  @override
  String get staffPendingInvites => 'بانتظار الاستخدام';

  @override
  String get staffNoPendingInvites => 'لا رموز معلّقة';

  @override
  String get staffAcceptTitle => 'الانضمام إلى متجر';

  @override
  String get staffAcceptCode => 'أدخل رمز الدعوة';

  @override
  String get staffAcceptJoin => 'انضمام';

  @override
  String get staffAcceptFailed => 'هذا الرمز غير صالح';

  @override
  String staffJoined(String store) {
    return 'أصبحت تعمل في $store';
  }

  @override
  String get staffEditPermissions => 'الصلاحيات';

  @override
  String get staffRoleDefaults => 'الافتراضي لهذا الدور';

  @override
  String get staffCustomised => 'مُخصَّص لهذا الشخص';

  @override
  String get staffResetToRole => 'العودة إلى افتراضي الدور';

  @override
  String get staffChangeRole => 'تغيير الدور';

  @override
  String get staffDeactivate => 'إيقاف';

  @override
  String get staffActivate => 'إعادة تفعيل';

  @override
  String get staffRemove => 'إزالة من المتجر';

  @override
  String get staffRemoveConfirm =>
      'إزالة هذا الشخص؟ تبقى ورديّاته ومبيعاته في السجل.';

  @override
  String get staffRemoved => 'تمت الإزالة';

  @override
  String get staffClockIn => 'تسجيل حضور';

  @override
  String get staffClockOut => 'تسجيل انصراف';

  @override
  String get staffClockedIn => 'أنت على الوردية';

  @override
  String get staffClockedOut => 'انتهت الوردية';

  @override
  String get staffSalesToday => 'مبيعات اليوم';

  @override
  String get staffNoPosSalesYet => 'ستظهر المبيعات هنا بعد تشغيل نقطة البيع.';

  @override
  String get staffEmpty => 'تعمل وحدك حتى الآن';

  @override
  String get staffEmptyHint => 'ادعُ مديراً أو أمين صندوق ليظهر هنا.';

  @override
  String get staffCouldNotLoad => 'تعذّر تحميل الفريق';

  @override
  String get staffNoShopYet => 'لست ضمن فريق أي متجر بعد';

  @override
  String get staffYou => 'أنت';

  @override
  String get staffOwnerBadge => 'المالك';

  @override
  String get staffCannotEditOwner => 'المالك يملك كل الصلاحيات دائماً.';

  @override
  String get staffNoPermission => 'لا يمكنك تغيير هذا';

  @override
  String get repTitle => 'تقارير المبيعات';

  @override
  String get repRangeToday => 'اليوم';

  @override
  String get repRangeWeek => 'آخر 7 أيام';

  @override
  String get repRangeMonth => 'آخر 30 يوماً';

  @override
  String get repRangeCustom => 'اختيار التواريخ';

  @override
  String get repCompareToPrevious => 'المقارنة بالفترة السابقة';

  @override
  String repRangeTooLong(int days) {
    return 'يغطي التقرير $days يوماً كحد أقصى في المرة الواحدة';
  }

  @override
  String get repRevenue => 'الإيرادات';

  @override
  String get repNetRevenue => 'صافي الإيرادات';

  @override
  String get repGrossValue => 'إجمالي المبيعات';

  @override
  String get repRefunded => 'المُعاد';

  @override
  String get repOrders => 'الطلبات';

  @override
  String get repItemsSold => 'الأصناف المباعة';

  @override
  String get repAverageOrder => 'متوسط العملية';

  @override
  String get repDailyRevenue => 'الإيرادات حسب اليوم';

  @override
  String get repByCategory => 'المبيعات حسب القسم';

  @override
  String get repTopProducts => 'الأكثر مبيعاً';

  @override
  String get repUncategorised => 'بلا قسم';

  @override
  String get repBySource => 'مصدر المبيعات';

  @override
  String get repByPaymentMethod => 'طريقة الدفع';

  @override
  String get repSourceDelivery => 'YouDrop';

  @override
  String get repSourceWalkIn => 'من المحل';

  @override
  String repSoldCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'بيع $count صنف',
      many: 'بيع $count صنفاً',
      few: 'بيعت $count أصناف',
      two: 'بيع صنفان',
      one: 'بيع صنف واحد',
      zero: 'لم يُبع شيء',
    );
    return '$_temp0';
  }

  @override
  String repOrdersTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عملية',
      many: '$count عملية',
      few: '$count عمليات',
      two: 'عمليتان',
      one: 'عملية واحدة',
      zero: 'لا مبيعات',
    );
    return '$_temp0';
  }

  @override
  String get repEmpty => 'لا مبيعات في هذه الفترة';

  @override
  String get repEmptyHint =>
      'وسّع الفترة، أو استورد السجل السابق لبدء التقارير.';

  @override
  String get repSyncHistory => 'استيراد المبيعات السابقة';

  @override
  String get repSyncStarted => 'يجري تجهيز سجلك…';

  @override
  String get repCouldNotLoad => 'تعذّر تحميل التقرير';

  @override
  String get repExportCsv => 'تصدير CSV';

  @override
  String get repExported => 'تم تصدير التقرير';

  @override
  String repGeneratedAt(Object when) {
    return 'احتُسب $when';
  }

  @override
  String get repNoChange => '—';

  @override
  String get repHistoryTitle => 'سجل المبيعات';

  @override
  String get repHistorySubtitle => 'عرض إيصالات المبيعات وإدارتها';

  @override
  String get repHistorySearch => 'ابحث برقم الإيصال أو الصنف';

  @override
  String get repHistoryEmpty => 'لا إيصالات في هذه الفترة';

  @override
  String get repHistoryCouldNotLoad => 'تعذّر تحميل سجل المبيعات';

  @override
  String get repStatusCompleted => 'مكتملة';

  @override
  String get repStatusPartiallyRefunded => 'مُعادة جزئياً';

  @override
  String get repStatusRefunded => 'مُعادة';

  @override
  String get repStatusVoided => 'ملغاة';

  @override
  String get repViewReceipt => 'عرض الإيصال';

  @override
  String get repFilterAll => 'الكل';

  @override
  String get merchantPartner => 'شريك تاجر';

  @override
  String get carrierPartner => 'شريك توصيل';

  @override
  String get backofficeOperator => 'مشغّل الإدارة';

  @override
  String get imageUnavailable => 'الصورة غير متاحة';

  @override
  String get openFullSizePhoto => 'افتح الصورة بالحجم الكامل';

  @override
  String photoPosition(int index, int count) {
    return '$index من $count';
  }

  @override
  String get close => 'إغلاق';

  @override
  String get previous => 'السابق';

  @override
  String get next => 'التالي';

  @override
  String get accountIntentSheetTitle => 'كيف ستستخدم YouDrop؟';

  @override
  String get accountIntentSheetSubtitle =>
      'اختر واحداً ثم تابع باستخدام Google. تتم مراجعة التوصيل والبيع قبل أن تبدأ، ويمكن للحساب التقدّم لواحد منهما فقط.';

  @override
  String get accountIntentCustomer => 'زبون';

  @override
  String get accountIntentCustomerBlurb => 'أريد أن أطلب';

  @override
  String get accountIntentRider => 'سائق توصيل';

  @override
  String get accountIntentRiderBlurb => 'أريد أن أوصّل';

  @override
  String get accountIntentSeller => 'بائع';

  @override
  String get accountIntentSellerBlurb => 'أريد أن أبيع';

  @override
  String get googleSignInCancelled =>
      'تم إلغاء تسجيل الدخول عبر Google. لم يتغيّر شيء.';

  @override
  String get googleSignInUnavailable =>
      'تسجيل الدخول عبر Google غير متاح بعد. يُرجى استخدام بريدك الإلكتروني أو هاتفك حالياً.';

  @override
  String get googleRoleNotAdded =>
      'تم تسجيل دخولك، لكن تعذّر إكمال إعداد حسابك. يُرجى الاختيار مجدداً.';

  @override
  String get googleExistingApplication =>
      'لدى هذا الحساب طلب انضمام بالفعل، لذا فتحناه بدلاً من بدء طلب جديد.';

  @override
  String get accountSetupTitle => 'خطوة أخيرة';

  @override
  String get accountSetupSubtitle =>
      'أخبرنا كيف ستستخدم YouDrop لإكمال إعداد حسابك.';

  @override
  String get wizAccountEmailNote =>
      'سنستخدم البريد الإلكتروني المرتبط بالحساب الذي سجّلت الدخول به.';

  @override
  String get wizAccountRefreshFailed =>
      'تم استلام طلبك، لكن تعذّر تحديث تسجيل دخولك. حاول مجدداً.';

  @override
  String get accountApplicationClosed =>
      'تم البتّ في طلب الشراكة على هذا الحساب مسبقاً، لذا لا يمكن إعادة فتحه من هنا. يُرجى التواصل مع الدعم.';

  @override
  String get accountAlreadyPartner =>
      'هذا الحساب شريك لدى YouDrop بالفعل، ولا يمكن للحساب الواحد أن يحمل أكثر من دور شريك واحد.';

  @override
  String get accountOtherApplication =>
      'لدى هذا الحساب طلب لدور آخر بالفعل، ولا يمكن للحساب الواحد التقدّم إلا لدور واحد.';

  @override
  String get accountEmailUnverified =>
      'لم يتم التحقق من البريد الإلكتروني لحسابك بعد، لذا لا يمكننا استلام طلب عليه حالياً.';

  @override
  String get wizAccountRolesRetry =>
      'تم استلام طلبك، لكن تعذّر إكمال إعداد حسابك. يُرجى المحاولة مجدداً.';

  @override
  String get offlinePill => 'غير متصل';

  @override
  String get offlineBanner =>
      'أنت غير متصل. سنرسل الطلبات المنتظِرة فور عودة الاتصال.';

  @override
  String get offlineBackOnline => 'عاد الاتصال';

  @override
  String get offlineSavedItems => 'المحفوظات';

  @override
  String get offlineModeBadge => 'وضع عدم الاتصال';

  @override
  String get offlineCachedCatalogTitle => 'الكتالوج المحفوظ';

  @override
  String get offlineLastPurchases => 'آخر مشترياتك المحفوظة';

  @override
  String offlinePricesAsOf(String when) {
    return 'الأسعار كما كانت في $when، وقد تكون تغيّرت منذ ذلك الحين.';
  }

  @override
  String get offlineQuickAdd => 'إضافة سريعة';

  @override
  String get offlineNeedsOptions => 'اختر الإضافات عند عودة الاتصال';

  @override
  String get offlineNothingSaved => 'لا شيء محفوظ بعد';

  @override
  String get offlineNothingSavedHint =>
      'نحفظ هنا ما تطلبه أثناء الاتصال، لتطلبه مجدداً حين ينقطع الإنترنت.';

  @override
  String get offlineOutboxTitle => 'بانتظار الإرسال';

  @override
  String offlineQueuedTitle(String store) {
    return '$store — بالانتظار';
  }

  @override
  String get offlineWillSend => 'سيُرسَل فور عودة الاتصال';

  @override
  String get offlineSending => 'جارٍ الإرسال…';

  @override
  String offlinePriceChanged(String total) {
    return 'أصبح المجموع $total. أكّد لإرسال الطلب بهذا السعر.';
  }

  @override
  String offlineSendAt(String total) {
    return 'أرسِل بـ $total';
  }

  @override
  String get offlineStale => 'ينتظر هذا الطلب منذ مدة. هل ما زلت تريده؟';

  @override
  String get offlineSendNow => 'أرسِل الآن';

  @override
  String offlineFailed(String reason) {
    return 'تعذّر تنفيذ هذا الطلب: $reason';
  }

  @override
  String get offlineDiscard => 'حذف';

  @override
  String get offlineDiscardTitle => 'حذف هذا الطلب؟';

  @override
  String get offlineDiscardBody => 'لم يُنفَّذ هذا الطلب، ولن يُرسَل.';

  @override
  String get offlineQueueTitle => 'تعذّر الوصول إلى YouDrop';

  @override
  String get offlineQueueBody =>
      'لم يصل طلبك بعد. يمكننا الاحتفاظ به على هذا الهاتف وإرساله تلقائياً عند عودة الاتصال، وإن تغيّر السعر فسنسألك أولاً.';

  @override
  String get offlineQueueAction => 'اطلب عند عودة الاتصال';

  @override
  String get offlineQueueCashOnly =>
      'وحدها الطلبات النقدية يمكنها انتظار عودة الاتصال. اختر الدفع نقداً، أو حاول مجدداً عند عودة الاتصال.';

  @override
  String get offlineQueued =>
      'حُفظ الطلب على هذا الهاتف، وسيُرسَل عند عودة الاتصال.';

  @override
  String get offlineQueueSaveFailed =>
      'تعذّر حفظ الطلب على هذا الهاتف، لذا لم يُحفَظ أي طلب.';

  @override
  String get offlineAlreadyPlaced =>
      'نجحت محاولتك السابقة بالفعل، وهذا هو الطلب الذي نفّذناه.';

  @override
  String offlineSent(String store) {
    return 'تم تنفيذ طلبك المنتظِر من $store.';
  }

  @override
  String get offlineQueueUnavailable =>
      'لا يمكن للطلبات المقسومة مع الأصدقاء انتظار عودة الاتصال، لأن حصة كل صديق تُربط بالطلب لحظة تنفيذه. حاول مجدداً عند عودة الاتصال.';

  @override
  String offlineQueuedWhenAmount(String when, String amount) {
    return 'حُفظ $when • $amount';
  }

  @override
  String get offlineMaybePlaced =>
      'تعذّر التأكد من وصول هذا الطلب. سنتحقق مجدداً تلقائياً، ولن يُنفَّذ مرتين.';

  @override
  String get offlineStaleMaybePlaced =>
      'تعذّر التأكد من وصول هذا الطلب، وقد مضى على انتظاره وقت. أرسِله مجدداً لتعرف: إن كان قد وصل فستحصل على ذلك الطلب نفسه، لا على طلب ثانٍ.';

  @override
  String get offlineSendAgain => 'أرسِل مجدداً';

  @override
  String get offlineDiscardMaybePlacedBody =>
      'ربما نُفِّذ هذا الطلب بالفعل، فقد تعذّر علينا التأكد. الحذف يزيله من هذا الهاتف فقط، لذا راجع «الطلبات» لتعرف إن كان قد وصل.';

  @override
  String get offlineUnconfirmedTitle => 'تعذّر تأكيد طلبك';

  @override
  String get offlineUnconfirmedLead =>
      'ربما وصل طلبك قبل انقطاع الاتصال، فراجع «الطلبات» عند عودة الاتصال.';

  @override
  String get offlineQueueResendBody =>
      'يمكننا الاحتفاظ به على هذا الهاتف وإرساله مجدداً عند عودة الاتصال. إن كان قد وصل فستحصل على ذلك الطلب لا على طلب ثانٍ، وإن تغيّر السعر فسنسألك أولاً.';

  @override
  String get offlineUnconfirmedRetry =>
      'تعذّر تأكيد طلبك، وربما يكون قد وصل. إعادة المحاولة آمنة ولن يُنفَّذ الطلب مرتين.';

  @override
  String get offlineQueueStandardOnly =>
      'لا يمكن للطلبات السريعة انتظار عودة الاتصال، لأن سعر التوصيل السريع لا يُحدَّد إلا عند تنفيذ الطلب. اختر «عادي»، أو حاول مجدداً عند عودة الاتصال.';

  @override
  String get offlineQueueTotalUnknown =>
      'تعذّر علينا تأكيد مجموع هذا الطلب لهذا العنوان، لذا لا يمكنه انتظار عودة الاتصال. حاول مجدداً عند عودة الاتصال.';

  @override
  String get carrCashNavLabel => 'التسوية';

  @override
  String get carrCashTitle => 'تسوية نقد السائقين';

  @override
  String get carrCashSubtitle => 'طابِق النقد الذي جمعه سائقوك مع ما يسلّمونه';

  @override
  String carrCashTodayChip(String date) {
    return 'اليوم: $date';
  }

  @override
  String carrCashDayChip(String date) {
    return 'يوم $date';
  }

  @override
  String get carrCashPickDay => 'أيّ يوم؟';

  @override
  String get carrCashKpiWithRiders => 'لدى سائقيك';

  @override
  String carrCashKpiWithRidersNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'مع $count سائق',
      many: 'مع $count سائقاً',
      few: 'مع $count سائقين',
      two: 'مع سائقَين',
      one: 'مع سائق واحد',
      zero: 'لا أحد يحمل نقداً',
    );
    return '$_temp0';
  }

  @override
  String get carrCashKpiHandedOver => 'تم تسليمه';

  @override
  String carrCashKpiHandedOverNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عملية تسليم في هذا اليوم',
      many: '$count عملية تسليم في هذا اليوم',
      few: '$count عمليات تسليم في هذا اليوم',
      two: 'عمليتا تسليم في هذا اليوم',
      one: 'عملية تسليم واحدة في هذا اليوم',
      zero: 'لا عمليات تسليم في هذا اليوم',
    );
    return '$_temp0';
  }

  @override
  String get carrCashKpiOwed => 'مستحق لـ YouDrop';

  @override
  String carrCashKpiOwedNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'بحوزة شركتك · $count طلب',
      many: 'بحوزة شركتك · $count طلباً',
      few: 'بحوزة شركتك · $count طلبات',
      two: 'بحوزة شركتك · طلبان',
      one: 'بحوزة شركتك · طلب واحد',
      zero: 'لا تحتفظ شركتك بأي نقد',
    );
    return '$_temp0';
  }

  @override
  String get carrCashKpiOverdue => 'متأخر';

  @override
  String carrCashKpiOverdueNote(int count, int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count سائق تجاوزوا حدّ $hours ساعة',
      many: '$count سائقاً تجاوزوا حدّ $hours ساعة',
      few: '$count سائقين تجاوزوا حدّ $hours ساعة',
      two: 'سائقان تجاوزا حدّ $hours ساعة',
      one: 'سائق واحد تجاوز حدّ $hours ساعة',
      zero: 'لا أحد تجاوز حدّ $hours ساعة',
    );
    return '$_temp0';
  }

  @override
  String carrCashOverdueSoftNote(int hours) {
    return 'بعض النقد محتفظ به منذ أكثر من $hours ساعة. اطلب من هؤلاء السائقين تسليمه.';
  }

  @override
  String get carrCashBalancesTitle => 'أرصدة السائقين';

  @override
  String get carrCashColRider => 'السائق';

  @override
  String get carrCashColCollected => 'المُحصَّل';

  @override
  String get carrCashColEarned => 'رسوم مكتسبة لك';

  @override
  String get carrCashColHolding => 'نقد للتسليم';

  @override
  String get carrCashColLastHandover => 'آخر تسليم';

  @override
  String get carrCashColStatus => 'الحالة';

  @override
  String get carrCashColActions => 'الإجراءات';

  @override
  String get carrCashStatusHolding => 'يحمل نقداً';

  @override
  String carrCashStatusOverdue(int hours) {
    return 'متأخر $hours ساعة';
  }

  @override
  String get carrCashStatusSettled => 'مُسوّى';

  @override
  String get carrCashActionSettle => 'تسوية';

  @override
  String get carrCashActionView => 'عرض';

  @override
  String get carrCashNever => 'أبداً';

  @override
  String get carrCashToday => 'اليوم';

  @override
  String get carrCashYesterday => 'أمس';

  @override
  String carrCashDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'منذ $count يوم',
      many: 'منذ $count يوماً',
      few: 'منذ $count أيام',
      two: 'منذ يومين',
      one: 'منذ يوم',
      zero: 'اليوم',
    );
    return '$_temp0';
  }

  @override
  String get carrCashNobodyYet => 'لم يحمل أيّ من سائقيك نقداً لشركتك بعد.';

  @override
  String get carrCashTableNote =>
      'المُحصَّل والرسوم تخصّ اليوم المختار. أمّا النقد للتسليم فهو كل ما لا يزال بحوزة السائق أيّاً كان تاريخ تحصيله. ما تدفعه شركتك لسائقيها متّفق عليه بينكم ولا يظهر هنا.';

  @override
  String carrCashSelectRider(String name) {
    return 'اختر $name';
  }

  @override
  String get carrCashSelectAll => 'اختر كل السائقين الذين يحملون نقداً';

  @override
  String get carrCashSettleSelected => 'تسوية المحدَّد';

  @override
  String carrCashSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count محدَّد',
      many: '$count محدَّداً',
      few: '$count محدَّدين',
      two: 'محدَّدان',
      one: 'محدَّد واحد',
      zero: 'لم يُحدَّد أحد',
    );
    return '$_temp0';
  }

  @override
  String get carrCashExportCsv => 'تصدير CSV';

  @override
  String carrCashExported(String file) {
    return 'تم حفظ $file';
  }

  @override
  String get carrCashCsvRiderId => 'معرّف السائق';

  @override
  String get carrCashCsvOrdersHeld => 'الطلبات المحتفظ بها';

  @override
  String get carrCashCsvOldest => 'أقدم تحصيل';

  @override
  String carrCashOrderCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count طلب',
      many: '$count طلباً',
      few: '$count طلبات',
      two: 'طلبان',
      one: 'طلب واحد',
      zero: 'لا طلبات',
    );
    return '$_temp0';
  }

  @override
  String get carrCashConfirmTitle => 'تسجيل عملية تسليم';

  @override
  String carrCashConfirmBody(String name, String amount, String orders) {
    return 'أكّد أنّ $name سلّم شركتك $amount نقداً عن $orders. هذا يُصفّي رصيده معك بالكامل ولا يمكن التراجع عنه.';
  }

  @override
  String carrCashConfirmBulkTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تسجيل $count عملية تسليم',
      many: 'تسجيل $count عملية تسليم',
      few: 'تسجيل $count عمليات تسليم',
      two: 'تسجيل عمليتي تسليم',
      one: 'تسجيل عملية تسليم واحدة',
      zero: 'لا عمليات تسليم',
    );
    return '$_temp0';
  }

  @override
  String get carrCashConfirmBulkBody =>
      'أكّد أنّ كل واحد من هؤلاء السائقين سلّم شركتك المبلغ الظاهر. يُصفّى كل رصيد بالكامل ولا يمكن التراجع عن أيّ منها.';

  @override
  String carrCashConfirmBulkTotal(String amount) {
    return 'المجموع $amount';
  }

  @override
  String get carrCashConfirmYes => 'نعم، سجّلها';

  @override
  String get carrCashMethodLabel => 'طريقة التسليم';

  @override
  String get carrCashMethodCash => 'تسليم نقدي';

  @override
  String get carrCashMethodBank => 'إيداع مصرفي';

  @override
  String get carrCashMethodWallet => 'تطبيق تحويل أموال';

  @override
  String get carrCashNoteLabel => 'ملاحظة (اختيارية)';

  @override
  String get carrCashNoteHint => 'أيّ شيء يجب أن يتذكّره المركز، مثل رقم الكيس';

  @override
  String carrCashRecorded(String amount, String name) {
    return 'تم تسجيل $amount من $name.';
  }

  @override
  String get carrCashReplayed =>
      'هذه العملية مسجّلة مسبقاً، لذا لم يُسجَّل شيء مرتين.';

  @override
  String carrCashAmountChanged(String name, String amount) {
    return 'يحمل $name الآن $amount، وليس المبلغ الذي أكّدته. لم يُسجَّل شيء؛ أعد العدّ.';
  }

  @override
  String carrCashAmountChangedUnknown(String name) {
    return 'تغيّر رصيد $name منذ فتحت الصفحة. لم يُسجَّل شيء؛ أعد التحميل ثم العدّ.';
  }

  @override
  String get carrCashRecordFailed =>
      'تعذّر التسجيل. لم يتغيّر شيء؛ حاول مجدداً.';

  @override
  String carrCashBulkDone(int done, int total) {
    return 'تم تسجيل $done من $total.';
  }

  @override
  String get carrCashLoadFailed =>
      'تعذّر تحميل نقد شركتك الآن. لا مشكلة في سجلاتك؛ حاول مجدداً.';

  @override
  String get carrCashTryAgain => 'حاول مجدداً';

  @override
  String get carrCashRiderTitle => 'تفاصيل تسوية السائق';

  @override
  String carrCashRiderSubtitle(String name) {
    return 'طابِق كيس النقد مع $name';
  }

  @override
  String get carrCashBack => 'العودة إلى التسوية';

  @override
  String get carrCashBadgeUnsettled => 'رصيد غير مُسوّى';

  @override
  String carrCashRiderSince(String date) {
    return 'يحمل نقداً لشركتك منذ $date';
  }

  @override
  String carrCashRatings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '($count تقييم)',
      many: '($count تقييماً)',
      few: '($count تقييمات)',
      two: '(تقييمان)',
      one: '(تقييم واحد)',
      zero: '(لا تقييمات)',
    );
    return '$_temp0';
  }

  @override
  String get carrCashRatingNew => 'سائق جديد';

  @override
  String get carrCashHeldTitle => 'توصيلات غير مُسوّاة';

  @override
  String get carrCashColOrder => 'رقم الطلب';

  @override
  String get carrCashColCash => 'إجمالي النقد';

  @override
  String get carrCashColFee => 'الرسم المكتسب لك';

  @override
  String get carrCashHeldEmpty =>
      'لا شيء للتسوية: هذا السائق لا يحمل أيّ نقد لشركتك.';

  @override
  String get carrCashSummaryTitle => 'ملخّص التسوية';

  @override
  String get carrCashSummaryCollected => 'نقد مُحصَّل لم يُسلَّم بعد';

  @override
  String get carrCashSummaryFees => 'رسوم مكتسبة لشركتك';

  @override
  String get carrCashSummaryDue => 'نقد مستحق لشركتك';

  @override
  String get carrCashSummaryKeeps =>
      'لا يحتفظ السائق بأيّ جزء من هذا النقد. ما تدفعه شركتك له متّفق عليه بينكما، والرسوم أعلاه تدفعها YouDrop لشركتك ولا تُقتطع من النقد.';

  @override
  String get carrCashConfirmSettlement => 'تأكيد التسوية';

  @override
  String get carrCashNothingToSettle => 'لا شيء للتسوية';

  @override
  String get carrCashHistoryTitle => 'سجلّ التسليمات';

  @override
  String carrCashHistoryItem(String date) {
    return 'تسليم · $date';
  }

  @override
  String carrCashHistoryDetail(String amount, String orders, String name) {
    return '$amount عن $orders، سجّله $name';
  }

  @override
  String carrCashHistoryDetailAnon(String amount, String orders) {
    return '$amount عن $orders';
  }

  @override
  String get carrCashHistoryEmpty => 'لم تُسجَّل أيّ عمليات تسليم بعد.';

  @override
  String get carrCashRiderNotFound => 'لم يعمل هذا السائق لدى شركتك من قبل.';

  @override
  String get carrCashBoTitle => 'بحوزة شركات التوصيل';

  @override
  String get carrCashBoOwes => 'مستحق للمنصة';

  @override
  String carrCashBoWithRiders(String amount) {
    return 'لدى سائقيها: $amount';
  }

  @override
  String carrCashBoLastPaid(String when) {
    return 'آخر دفعة $when';
  }

  @override
  String get carrCashBoNeverPaid => 'لم تدفع بعد';

  @override
  String get carrCashBoHoldsNothing => 'لا تحتفظ بشيء بعد';

  @override
  String get carrCashBoRecordPayment => 'تسجيل دفعة';

  @override
  String get carrCashBoConfirmTitle => 'تسجيل دفعة';

  @override
  String carrCashBoConfirmBody(String company, String amount, String orders) {
    return 'أكّد أنّ $company دفعت للمنصة $amount عن $orders. هذا يُصفّي كل ما تحتفظ به الشركة ولا يمكن التراجع عنه.';
  }

  @override
  String get carrCashBoConfirmYes => 'نعم، تم الدفع';

  @override
  String carrCashBoRecorded(String amount, String company) {
    return 'تم تسجيل $amount من $company.';
  }

  @override
  String get carrCashBoNothing =>
      'لم يكن هناك مبلغ مستحق؛ ربما سجّله أحدهم مسبقاً.';

  @override
  String carrCashBoAmountChanged(String company, String amount) {
    return 'تحتفظ $company الآن بـ $amount، وليس المبلغ الذي أكّدته. لم يُسجَّل شيء.';
  }

  @override
  String carrCashBoFailed(String error) {
    return 'تعذّر التسجيل: $error';
  }

  @override
  String get carrCashBoOverdueNote =>
      'بعض النقد لم يُسلَّم منذ مدة تتجاوز الحدّ الذي تعتمده المنصة. لا خطأ في السجلات: هذا مال لم يصل إلى المصرف بعد.';

  @override
  String get carrCashBoLoadFailed =>
      'تعذّر تحميل ما تحتفظ به شركات التوصيل حالياً. بقية هذه الصفحة غير متأثرة.';

  @override
  String get carrCashBoMethodLabel => 'طريقة الدفع (اختياري)';

  @override
  String get dekkaneBrowseTitle => 'حيّك';

  @override
  String dekkaneBrowseSubRegion(String region) {
    return 'دكاكين $region المحلية';
  }

  @override
  String dekkaneAreaInRegion(String area, String region) {
    return '$area، $region';
  }

  @override
  String get dekkaneEntrySub => 'الدكاكين والمحلات الصغيرة حول عنوانك';

  @override
  String get dekkaneFilterOpenNow => 'مفتوح الآن';

  @override
  String get dekkaneFilterOnGenerator => 'على المولّد الآن';

  @override
  String get dekkaneFilterNew => 'جديد على YouDrop';

  @override
  String get dekkaneExpandMap => 'توسيع الخريطة التفاعلية';

  @override
  String get dekkaneNearbyShops => 'محلات قريبة منك';

  @override
  String get dekkaneLocalShops => 'محلات الحي';

  @override
  String dekkaneDistanceMetres(int metres) {
    final intl.NumberFormat metresNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String metresString = metresNumberFormat.format(metres);

    return 'على بُعد $metresString م';
  }

  @override
  String dekkaneDistanceKm(double km) {
    final intl.NumberFormat kmNumberFormat =
        intl.NumberFormat.decimalPatternDigits(
            locale: localeName, decimalDigits: 1);
    final String kmString = kmNumberFormat.format(km);

    return 'على بُعد $kmString كم';
  }

  @override
  String get dekkaneGeneratorActive => 'المولّد يعمل';

  @override
  String get dekkaneTrustedLocal => 'محلّي موثوق';

  @override
  String get dekkaneCouldNotLoadShops => 'تعذّر تحميل المحلات من حولك';

  @override
  String get dekkanePinAddressPrompt =>
      'ثبّت عنوانك على الخريطة لترى أقرب المحلات إليك وكم يبعد كلّ منها.';

  @override
  String get dekkaneNoShopsNearby => 'لا توجد محلات قرب هذا العنوان بعد';

  @override
  String get dekkaneMapTitle => 'المحلات على الخريطة';

  @override
  String dekkaneOpenClosesAt(String time) {
    return 'مفتوح · يغلق $time';
  }

  @override
  String get dekkaneShopInventory => 'بضاعة المحل';

  @override
  String dekkaneLbpAmount(int amount) {
    final intl.NumberFormat amountNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String amountString = amountNumberFormat.format(amount);

    return '$amountString ل.ل.';
  }

  @override
  String get dekkaneAddOneMore => 'أضف واحداً آخر';

  @override
  String get dekkaneMerchNeighborhood => 'الحي';

  @override
  String get dekkaneMerchNeighborhoodHint => 'مثلاً: مار مخايل';

  @override
  String get dekkaneMerchNeighborhoodHelp =>
      'يظهر تحت اسم محلّك عندما يفتحه الزبائن من قائمة حيّهم.';

  @override
  String get dekkaneMerchNeighborhoodTooLong => 'يجب ألّا يتجاوز 80 حرفاً';

  @override
  String get dekkaneCouldNotLoadShelf => 'تعذّر تحميل رفوف المحل';

  @override
  String get dekkaneBrowseTitleAll => 'المحلات على YouDrop';

  @override
  String get dekkaneBrowseSubAll => 'كل المحلات، الأعلى تقييماً أولاً';

  @override
  String get dekkaneAllShops => 'كل المحلات';

  @override
  String dekkanePowerUpdatedMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'آخر تحديث منذ $minutes دقيقة',
      many: 'آخر تحديث منذ $minutes دقيقة',
      few: 'آخر تحديث منذ $minutes دقائق',
      two: 'آخر تحديث منذ دقيقتين',
      one: 'آخر تحديث منذ دقيقة',
      zero: 'حُدِّث للتو',
    );
    return '$_temp0';
  }

  @override
  String dekkanePowerUpdatedHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'آخر تحديث منذ $hours ساعة',
      many: 'آخر تحديث منذ $hours ساعة',
      few: 'آخر تحديث منذ $hours ساعات',
      two: 'آخر تحديث منذ ساعتين',
      one: 'آخر تحديث منذ ساعة',
      zero: 'حُدِّث للتو',
    );
    return '$_temp0';
  }

  @override
  String dekkaneSearchedNearest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم البحث في أقرب $count محل فقط',
      many: 'تم البحث في أقرب $count محلاً فقط',
      few: 'تم البحث في أقرب $count محلات فقط',
      two: 'تم البحث في أقرب محلّين فقط',
      one: 'تم البحث في أقرب محل فقط',
      zero: 'لم يتم البحث في أي محل',
    );
    return '$_temp0';
  }

  @override
  String get attendanceNavShifts => 'الورديات والحضور';

  @override
  String get attendanceTitle => 'حضور السائقين وسجلّ الورديات';

  @override
  String get attendanceSubtitle =>
      'تابِع تسجيلات الدخول اليومية والتأخير والغياب وتعديلات الورديات';

  @override
  String attendanceForMonth(String month) {
    return 'الحضور وسجلّات الدوام لشهر $month';
  }

  @override
  String get attendanceBackToRiders => 'العودة إلى السائقين';

  @override
  String get attendanceManualLog => 'تسجيل حضور يدوي';

  @override
  String get attendancePrevMonth => 'الشهر السابق';

  @override
  String get attendanceNextMonth => 'الشهر التالي';

  @override
  String get attendanceLegendPresent => 'حاضر';

  @override
  String get attendanceLegendLate => 'متأخر';

  @override
  String get attendanceLegendAbsent => 'غائب';

  @override
  String get attendanceLegendOff => 'يوم عطلة';

  @override
  String get attendanceLegendOnDuty => 'في الخدمة';

  @override
  String get attendanceWeekMon => 'إثنين';

  @override
  String get attendanceWeekTue => 'ثلاثاء';

  @override
  String get attendanceWeekWed => 'أربعاء';

  @override
  String get attendanceWeekThu => 'خميس';

  @override
  String get attendanceWeekFri => 'جمعة';

  @override
  String get attendanceWeekSat => 'سبت';

  @override
  String get attendanceWeekSun => 'أحد';

  @override
  String get attendanceAggregatesTitle => 'ملخّص الحضور';

  @override
  String get attendanceDaysWorked => 'أيام العمل';

  @override
  String get attendanceAbsences => 'الغياب';

  @override
  String get attendanceTimesLate => 'مرات التأخير';

  @override
  String get attendanceOvertime => 'الساعات الإضافية المتراكمة';

  @override
  String get attendanceHoursOnDuty => 'ساعات الخدمة';

  @override
  String get attendanceManualHours => 'ساعات مسجّلة يدويًا';

  @override
  String get attendanceExcusedDays => 'أعذار أو مرض أو إجازة';

  @override
  String attendanceDaysCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count يوم',
      many: '$count يومًا',
      few: '$count أيام',
      two: 'يومان',
      one: 'يوم واحد',
      zero: '0 يوم',
    );
    return '$_temp0';
  }

  @override
  String attendanceHoursValue(String hours) {
    return '$hours ساعة';
  }

  @override
  String attendanceHoursShort(String hours) {
    return '$hours س';
  }

  @override
  String get attendanceLogsTitle => 'أحدث سجلّات الدخول والخروج';

  @override
  String get attendanceColDate => 'التاريخ';

  @override
  String get attendanceColShift => 'الوردية المجدولة';

  @override
  String get attendanceColClockIn => 'الدخول';

  @override
  String get attendanceColClockOut => 'الخروج';

  @override
  String get attendanceColHours => 'الساعات';

  @override
  String get attendanceColStatus => 'الحالة';

  @override
  String get attendanceColNotes => 'ملاحظات';

  @override
  String attendanceShiftLabel(String name, String start, String end) {
    return '$name ($start - $end)';
  }

  @override
  String get attendanceStatusOnTime => 'في الموعد';

  @override
  String get attendanceStatusLate => 'دخول متأخر';

  @override
  String get attendanceStatusAbsent => 'غائب';

  @override
  String get attendanceStatusPending => 'لم يصل بعد';

  @override
  String get attendanceStatusDayOff => 'يوم عطلة';

  @override
  String get attendanceStatusExtra => 'عمل في يوم عطلة';

  @override
  String get attendanceStatusWorked => 'في الخدمة';

  @override
  String get attendanceStatusLateExcused => 'متأخر (بعذر)';

  @override
  String get attendanceStatusExcused => 'غياب بعذر';

  @override
  String get attendanceStatusSick => 'إجازة مرضية';

  @override
  String get attendanceStatusLeave => 'إجازة';

  @override
  String get attendanceOnShiftNow => 'في الوردية الآن';

  @override
  String get attendanceAutoClosed => 'أُغلقت تلقائيًا: انقطعت الإشارة';

  @override
  String attendanceLateBy(int minutes) {
    return 'متأخر $minutes دقيقة';
  }

  @override
  String attendanceOvertimeNote(int minutes) {
    return '$minutes دقيقة إضافية';
  }

  @override
  String get attendanceLoggedByHand => 'مسجّل يدويًا';

  @override
  String get attendanceNoSchedule =>
      'لا توجد وردية مجدولة لهذا السائق، لذا يظهر وقت الخدمة فقط.';

  @override
  String get attendanceEmptyMonth =>
      'لا يوجد دوام مسجّل لهذا الشهر. يبدأ السجلّ منذ بدء تتبّع الدوام، ولا يُضاف أي شيء بأثر رجعي.';

  @override
  String attendanceZoneNote(String zone) {
    return 'تُقسَّم الأيام حسب المنطقة الزمنية $zone.';
  }

  @override
  String get attendanceNotOnFleet =>
      'هذا السائق غير مرتبط بأسطولك في نظام التتبّع بعد، لذا لا يمكن عرض حضوره. يُربط عندما يصل خبر تعيينه إلى نظام التتبّع، أو عندما ينقل طلبًا لشركتك.';

  @override
  String get attendanceLoadFailed => 'تعذّر تحميل الحضور حاليًا.';

  @override
  String attendanceLogTitle(String name) {
    return 'تسجيل حضور $name';
  }

  @override
  String get attendanceLogStatus => 'ما الذي حدث';

  @override
  String get attendanceLogChooseStatus => 'اختر الحالة';

  @override
  String get attendanceKindPresent => 'حاضر (لم يظهر في التطبيق)';

  @override
  String get attendanceKindLateExcused => 'متأخر بعذر';

  @override
  String get attendanceKindAbsentExcused => 'غائب بعذر';

  @override
  String get attendanceKindSick => 'مريض';

  @override
  String get attendanceKindLeave => 'في إجازة';

  @override
  String get attendanceLogClockIn => 'وقت الدخول (اختياري)';

  @override
  String get attendanceLogClockOut => 'وقت الخروج (اختياري)';

  @override
  String get attendanceLogNote => 'ملاحظة (اختيارية)';

  @override
  String get attendanceLogSave => 'حفظ السجل';

  @override
  String get attendanceLogWithdraw => 'حذف السجل';

  @override
  String get attendanceLogSaved => 'تم حفظ سجل الحضور.';

  @override
  String get attendanceLogRemoved =>
      'تم حذف السجل. يعرض اليوم ما سجّله التطبيق.';

  @override
  String get attendanceLogTimesRule =>
      'تُسجَّل الأوقات في يوم الحضور فقط، ويجب إدخال وقتي الدخول والخروج معًا.';

  @override
  String get attendanceLogManualNote =>
      'تُحتسب الساعات المُدخلة هنا ساعاتٍ يدوية، وليست دليلًا من التطبيق، ويُتجاهَل إدخالها في يوم يُظهره التطبيق أصلًا.';

  @override
  String get attendanceLogFutureRule =>
      'اليوم الذي لم يأتِ بعد لا يمكن تسجيله إلا إجازةً أو مرضًا أو غيابًا بعذر.';

  @override
  String get attendanceTimeInvalid => 'استخدم صيغة 24 ساعة مثل 08:00.';

  @override
  String get attendanceShiftsTitle => 'جداول الورديات';

  @override
  String get attendanceShiftsSubtitle =>
      'حدّد الورديات التي يعمل بها سائقوك، ثم افتح الحضور الشهري لأيٍّ منهم.';

  @override
  String get attendanceShiftsCard => 'الورديات';

  @override
  String get attendanceAddShift => 'إضافة وردية';

  @override
  String get attendanceNoShifts =>
      'لا توجد ورديات بعد. يُعامَل السائقون دون وردية كعاملين أحرار: لا تأخير ولا غياب.';

  @override
  String attendanceShiftGrace(int minutes) {
    return 'مهلة $minutes دقيقة';
  }

  @override
  String attendanceShiftRiders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count سائق',
      many: '$count سائقًا',
      few: '$count سائقين',
      two: 'سائقان',
      one: 'سائق واحد',
      zero: 'لا سائقين',
    );
    return '$_temp0';
  }

  @override
  String get attendanceShiftOvernight => 'تنتهي في اليوم التالي';

  @override
  String get attendanceRetireShift => 'إيقاف الوردية';

  @override
  String get attendanceRetireBlocked =>
      'انقل السائقين في هذه الوردية إلى وردية أخرى أولًا.';

  @override
  String get attendanceShiftRetired => 'تم إيقاف الوردية.';

  @override
  String get attendanceRidersCard => 'السائقون';

  @override
  String get attendanceColRider => 'السائق';

  @override
  String get attendanceColCurrentShift => 'الوردية';

  @override
  String get attendanceColActions => 'إجراءات';

  @override
  String get attendanceFreelancer => 'بلا جدول (عمل حر)';

  @override
  String get attendanceChangeShift => 'تغيير الوردية';

  @override
  String get attendanceOpenAttendance => 'الحضور';

  @override
  String attendanceUpcomingShift(String name, String date) {
    return '$name اعتبارًا من $date';
  }

  @override
  String get attendanceNoRiders => 'لا يوجد سائقون في أسطولك بعد.';

  @override
  String get attendanceNewShiftTitle => 'وردية جديدة';

  @override
  String get attendanceShiftName => 'الاسم';

  @override
  String get attendanceShiftStart => 'تبدأ (HH:mm)';

  @override
  String get attendanceShiftEnd => 'تنتهي (HH:mm)';

  @override
  String get attendanceShiftDays => 'الأيام';

  @override
  String get attendanceShiftGraceField =>
      'المهلة قبل احتساب التأخير (بالدقائق)';

  @override
  String get attendanceShiftImmutable =>
      'لا يمكن تعديل ساعات الوردية لاحقًا. لتغييرها، أضِف وردية جديدة وانقل السائقين إليها، لتبقى الأيام السابقة على الوردية التي عُمل بها.';

  @override
  String get attendanceCreateShift => 'إنشاء الوردية';

  @override
  String get attendanceShiftCreated => 'تم إنشاء الوردية.';

  @override
  String get attendanceShiftNeedsName => 'أدخل اسمًا للوردية.';

  @override
  String get attendanceShiftNeedsDays => 'اختر يومًا واحدًا على الأقل.';

  @override
  String get attendanceShiftSameTimes =>
      'لا يمكن أن تبدأ الوردية وتنتهي في الوقت نفسه.';

  @override
  String get attendanceGraceInvalid => 'أدخل عدد دقائق بين 0 و120.';

  @override
  String attendanceAssignTitle(String name) {
    return 'وردية $name';
  }

  @override
  String get attendanceAssignFrom => 'ابتداءً من';

  @override
  String get attendanceAssignNote =>
      'تبدأ الجداول اليوم أو لاحقًا. بعد أن تبدأ وردية اليوم، أو بعد أن يعمل السائق اليوم، يسري أي تغيير لليوم ابتداءً من الغد، لتبقى الأيام السابقة واليوم الجاري على الجدول الذي تُحتسب عليه.';

  @override
  String get attendanceAssignSave => 'حفظ الجدول';

  @override
  String get attendanceAssignSaved => 'تم تحديث الجدول.';

  @override
  String get attendanceHistoryLimit =>
      'هذا الشهر أقدم من سجلّ الدوام الذي تحتفظ به المنصّة، لذا لا يمكن عرضه بعد الآن.';

  @override
  String get attendanceManualTag => 'يدوي';

  @override
  String get attendanceTypedByHand =>
      'أُدخل يدويًا في سجل الحضور اليدوي، ولم يسجّله التطبيق';

  @override
  String get attendanceLogPresentKeepsLate =>
      'تسجيل الحضور لا يلغي الدخول المتأخر. لاعتباره بعذر، اختر «متأخر بعذر».';

  @override
  String get attendanceLogChecking =>
      'جارٍ التحقق من وجود سجل سابق لهذا اليوم…';

  @override
  String get attendanceLogCheckFailed =>
      'تعذّر التحقق من وجود سجل سابق لهذا اليوم، لذا لا يمكن الحفظ له بعد. اختر التاريخ مجددًا لإعادة المحاولة.';

  @override
  String attendanceRetiredShifts(int count) {
    return 'الورديات الموقوفة ($count)';
  }

  @override
  String get attendanceRetireKeepsHistory =>
      'تبقى الأيام السابقة محسوبة على هذه الوردية. إيقافها يمنع اختيارها في الجداول الجديدة فقط.';

  @override
  String attendanceLiveOnDuty(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'مباشر: $count سائق في الخدمة',
      many: 'مباشر: $count سائقًا في الخدمة',
      few: 'مباشر: $count سائقين في الخدمة',
      two: 'مباشر: سائقان في الخدمة',
      one: 'مباشر: سائق واحد في الخدمة',
      zero: 'مباشر: لا سائقين في الخدمة',
    );
    return '$_temp0';
  }

  @override
  String get carrRidersNavReconciliation => 'التسويات';

  @override
  String get carrRidersNavRidersHr => 'شؤون السائقين';

  @override
  String get carrRidersNavDirectory => 'دليل السائقين';

  @override
  String get carrRidersNavStatement => 'كشف الحساب';

  @override
  String get carrRidersTitle => 'دليل شؤون السائقين';

  @override
  String get carrRidersSubtitle => 'إدارة ملفات السائقين وحالاتهم ومناطقهم';

  @override
  String get carrRidersStatTotal => 'إجمالي السائقين المنضمّين';

  @override
  String get carrRidersStatTotalNote => 'أسطول الشركة المسجّل';

  @override
  String get carrRidersStatOnDuty => 'في الخدمة الآن';

  @override
  String get carrRidersStatOnDutyNote => 'متاحون أو في مهمة';

  @override
  String get carrRidersStatSignalLost => 'انقطعت الإشارة';

  @override
  String get carrRidersStatSignalLostNote =>
      'في الخدمة، لكن هواتفهم توقفت عن الإرسال';

  @override
  String get carrRidersStatOffline => 'غير متصلين / غير نشطين';

  @override
  String get carrRidersStatOfflineNote => 'أعلنوا أنهم خارج الخدمة';

  @override
  String get carrRidersPresenceUnknown => 'تعذّرت قراءة حالة التواجد حالياً';

  @override
  String get carrRidersSearchHint => 'ابحث عن السائقين بالاسم أو الرقم...';

  @override
  String get carrRidersZoneAll => 'المنطقة: الكل';

  @override
  String carrRidersZoneValue(String zone) {
    return 'المنطقة: $zone';
  }

  @override
  String get carrRidersZoneTooltip =>
      'المنطقة هنا هي التي كتبها كل سائق في طلب انضمامه';

  @override
  String get carrRidersVehicleAll => 'المركبة: الكل';

  @override
  String carrRidersVehicleValue(String vehicle) {
    return 'المركبة: $vehicle';
  }

  @override
  String get carrRidersVehicleMotorcycle => 'دراجة نارية';

  @override
  String get carrRidersVehicleCar => 'سيارة';

  @override
  String get carrRidersVehicleBicycle => 'دراجة هوائية';

  @override
  String get carrRidersVehicleVan => 'شاحنة صغيرة';

  @override
  String get carrRidersVehicleTruck => 'شاحنة';

  @override
  String get carrRidersAddRider => 'إضافة سائق';

  @override
  String get carrRidersAddRiderTooltip =>
      'وافق على شخص تقدّم للعمل سائقاً لديك';

  @override
  String get carrRidersAddRiderUnavailable =>
      'تعذّرت قراءة الطلبات حالياً، لذا لا يمكن الموافقة على أحد من هنا';

  @override
  String get carrRidersManageProfile => 'إدارة الملف';

  @override
  String carrRidersDeliveredToday(int count) {
    return '($count اليوم)';
  }

  @override
  String get carrRidersRatingNew => 'جديد';

  @override
  String get carrRidersStatusActive => 'نشط';

  @override
  String get carrRidersStatusSignalLost => 'انقطعت الإشارة';

  @override
  String get carrRidersStatusOffline => 'غير متصل';

  @override
  String get carrRidersStatusSuspended => 'موقوف';

  @override
  String get carrRidersStatusOnAJob => 'في مهمة';

  @override
  String get carrRidersNoMatch => 'لا يوجد سائق مطابق.';

  @override
  String carrRidersShowingOnly(String filter) {
    return 'المعروض فقط: $filter';
  }

  @override
  String get carrRidersShowEveryone => 'عرض الجميع';

  @override
  String get carrRidersDirectoryFootnote =>
      'المنطقة هي التي ذكرها كل سائق في طلبه — لا تعيّن المنصّة السائقين إلى مناطق تغطيتك. التقييم هو ما تركه العملاء عبر جميع توصيلات السائق. تظهر حالة التواجد هنا بعد أن يحمل السائق عملاً لشركتك، لذا لا تظهر لمن لم يفعل ذلك بعد.';

  @override
  String get carrRidersWaitingTitle => 'إضافة سائق';

  @override
  String carrRidersWaitingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count شخص ينتظرون العمل لديك',
      many: '$count شخصًا ينتظرون العمل لديك',
      few: '$count أشخاص ينتظرون العمل لديك',
      two: 'شخصان ينتظران العمل لديك',
      one: 'شخص واحد ينتظر العمل لديك',
      zero: 'لا أحد ينتظر العمل لديك',
    );
    return '$_temp0';
  }

  @override
  String get carrRidersWaitingEmpty =>
      'لم يتقدّم أحد للعمل سائقاً لديك. ينضمّ السائقون إلى الأسطول بتقديم طلب — ولا توجد طريقة لإنشاء سائق مباشرة.';

  @override
  String get carrRidersApprove => 'موافقة';

  @override
  String get carrRidersOnYourFleet => 'ضمن أسطولك';

  @override
  String carrRidersSuspendTitle(String name) {
    return 'إيقاف $name';
  }

  @override
  String carrRidersReinstateTitle(String name) {
    return 'إعادة $name إلى العمل';
  }

  @override
  String get carrRidersSuspendBody =>
      'يحتفظ بتسجيل دخوله وسجلّه، ويتوقف عرض العمل عليه. يمكنك إعادته في أي وقت.';

  @override
  String get carrRidersReinstateBody =>
      'يمكن عرض العمل عليه مجدداً فور حفظ هذا.';

  @override
  String get carrRidersChooseReason => 'اختر سبباً';

  @override
  String get carrRidersNoteHint => 'ملاحظة للسجل (اختيارية)';

  @override
  String get carrRidersSuspendRider => 'إيقاف السائق';

  @override
  String get carrRidersReinstateRider => 'إعادة السائق';

  @override
  String carrRidersSuspendedToast(String name) {
    return 'تم إيقاف $name ولن يُعرض عليه عمل.';
  }

  @override
  String carrRidersReinstatedToast(String name) {
    return 'يمكن لـ$name استلام العمل مجدداً.';
  }

  @override
  String get carrRidersReasonFraud => 'احتيال';

  @override
  String get carrRidersReasonAbuse => 'إساءة';

  @override
  String get carrRidersReasonNonPayment => 'عدم الدفع';

  @override
  String get carrRidersReasonPolicyViolation => 'مخالفة السياسة';

  @override
  String get carrRidersReasonPartnerRequest => 'بطلب من الشريك';

  @override
  String get carrRidersReasonOther => 'سبب آخر';

  @override
  String get carrRidersProfileTitle => 'ملف السائق';

  @override
  String get carrRidersProfileSubtitle => 'المستندات وتفاصيل العمل والأداء';

  @override
  String get carrRidersBackToDirectory => 'العودة إلى السائقين';

  @override
  String carrRidersBadgeId(String code) {
    return 'رقم الشارة: $code';
  }

  @override
  String get carrRidersPhone => 'الهاتف';

  @override
  String get carrRidersEmail => 'البريد الإلكتروني';

  @override
  String get carrRidersLastSeen => 'آخر ظهور';

  @override
  String get carrRidersNoPresenceYet => 'لا توجد حالة خدمة أو موقع بعد';

  @override
  String get carrRidersStaleNote =>
      'أعلن أنه في الخدمة، لكن آخر موقع قديم جداً لإسناد المهام إليه.';

  @override
  String get carrRidersNoApplication =>
      'أضافت المنصّة هذا السائق مباشرة، لذا لا يوجد طلب في السجل — لا اسم ولا بيانات تواصل ولا مستندات لعرضها.';

  @override
  String get carrRidersDocumentsTitle => 'التحقق من المستندات';

  @override
  String get carrRidersDocNationalId => 'الهوية الوطنية';

  @override
  String get carrRidersDocDrivingLicence => 'رخصة القيادة';

  @override
  String get carrRidersDocVehicleRegistration => 'تسجيل المركبة';

  @override
  String get carrRidersDocVerified => 'موثّق';

  @override
  String get carrRidersDocWaiting => 'قيد المراجعة';

  @override
  String get carrRidersDocRefused => 'مرفوض';

  @override
  String get carrRidersDocNotUploaded => 'لم يُرفع';

  @override
  String get carrRidersDocOpen => 'فتح المستند';

  @override
  String get carrRidersCouldNotRead => 'تعذّرت القراءة حالياً.';

  @override
  String get carrRidersAvgRating => 'متوسط التقييم';

  @override
  String carrRidersHappyCustomers(int percent) {
    return '$percent% من العملاء راضون';
  }

  @override
  String get carrRidersNoRatingsYet => 'لا توجد تقييمات بعد';

  @override
  String carrRidersDeliveriesWindow(int days) {
    return 'التوصيلات، آخر $days يوماً';
  }

  @override
  String carrRidersClaimedCaption(int claimed, int cancelled) {
    return '$claimed مُستلمة، $cancelled أُلغيت بعد الاستلام';
  }

  @override
  String get carrRidersCompletionRate => 'نسبة الإنجاز';

  @override
  String get carrRidersCompletionCaption => 'ما وُصّل من المُستلم، لشركتك';

  @override
  String get carrRidersNothingClaimed => 'لم يُستلم شيء في هذه الفترة';

  @override
  String get carrRidersDeliveredTodayLabel => 'وُصّل اليوم';

  @override
  String get carrRidersDeliveredTodayCaption => 'لشركتك، منذ منتصف الليل';

  @override
  String carrRidersOutputTitle(int days) {
    return 'ناتج التوصيل، آخر $days يوماً';
  }

  @override
  String get carrRidersOutputEmpty => 'لا توجد توصيلات في هذه الفترة';

  @override
  String carrRidersOutputNote(String zone) {
    return 'تُقسَم الأيام حسب المنطقة الزمنية $zone، ولا تُحتسب إلا التوصيلات التي تمّت لشركتك.';
  }

  @override
  String carrRidersHoursTitle(int days) {
    return 'ساعات الخدمة، آخر $days أيام';
  }

  @override
  String carrRidersHoursValue(String hours) {
    return '$hours س';
  }

  @override
  String carrRidersHoursTotal(String hours) {
    return '$hours س إجمالاً';
  }

  @override
  String carrRidersShifts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نوبة',
      many: '$count نوبة',
      few: '$count نوبات',
      two: 'نوبتان',
      one: 'نوبة واحدة',
      zero: 'لا نوبات',
    );
    return '$_temp0';
  }

  @override
  String get carrRidersHoursNone => 'لا توجد ساعات خدمة لعرضها لشركتك.';

  @override
  String carrRidersHoursZone(String zone) {
    return 'تُقسَم الأيام حسب المنطقة الزمنية $zone، كما يوردها الخادم.';
  }

  @override
  String get carrRidersEmploymentTitle => 'تفاصيل العمل';

  @override
  String get carrRidersStartDate => 'تاريخ البدء';

  @override
  String get carrRidersApplied => 'تاريخ التقديم';

  @override
  String get carrRidersRegion => 'المنطقة (من طلبه)';

  @override
  String get carrRidersVehicle => 'المركبة';

  @override
  String get carrRidersEmploymentNote =>
      'نوع العقد وأجر التوصيل وتعيين المنطقة غير مسجّلة على هذه المنصّة.';

  @override
  String get carrRidersSuspendUnavailable =>
      'يتم الإيقاف عبر طلب السائق لديك. أضافت المنصّة هذا السائق مباشرة، لذا اطلب من YouDrop إيقافه.';

  @override
  String get carrRidersTerminate => 'إنهاء العقد';

  @override
  String carrRidersTerminateTitle(String name) {
    return 'إنهاء عقد $name؟';
  }

  @override
  String carrRidersTerminateBody(String name) {
    return 'يخرج $name من أسطولك فوراً ولا يُعرض عليه أي من عملك. يحتفظ بتسجيل دخوله في YouDrop وبسجلّه، لكنه لا يصبح من سائقي YouDrop: لا يمكنه تولّي أي عمل إلى أن تعيّنه شركة أخرى أو تضمّه YouDrop إلى سائقيها.';
  }

  @override
  String get carrRidersTerminateJobs =>
      'المهام الجارية: ما دام يحمل مهمة لك، يُرفض هذا الإجراء حتى تُسلَّم تلك المهمة أو تُلغى. لا يُسقَط شيء مما يحمله ولا يُسلَّم لشخص آخر.';

  @override
  String get carrRidersTerminateMoney =>
      'استلم منه أولاً أي نقد تحصيل يحمله لك. إنهاء العقد لا يسوّي أي مبالغ: ما كسبه وما حصّله يبقى في السجل كما هو تماماً.';

  @override
  String get carrRidersTerminateUndo =>
      'إعادته إلى أسطولك لاحقاً تعني تعيينه من جديد.';

  @override
  String get carrRidersTerminateConfirm => 'إنهاء العقد';

  @override
  String carrRidersTerminated(String name) {
    return 'لم يعد $name ضمن أسطولك.';
  }

  @override
  String carrRidersTerminateCarrying(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'يحمل $count من مهامك الآن. يمكن إنهاء عقده بعد تسليمها أو إلغائها.',
      many:
          'يحمل $count من مهامك الآن. يمكن إنهاء عقده بعد تسليمها أو إلغائها.',
      few: 'يحمل $count من مهامك الآن. يمكن إنهاء عقده بعد تسليمها أو إلغائها.',
      two:
          'يحمل مهمتين من مهامك الآن. يمكن إنهاء عقده بعد تسليمهما أو إلغائهما.',
      one: 'يحمل إحدى مهامك الآن. يمكن إنهاء عقده بعد تسليمها أو إلغائها.',
      zero: 'لا يحمل أي مهمة لك الآن.',
    );
    return '$_temp0';
  }

  @override
  String get carrRidersNotOnFleet => 'لم يعد هذا السائق ضمن أسطولك.';

  @override
  String carrRidersNoPresenceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count سائق آخر بلا حالة خدمة أو موقع بعد',
      many: '$count سائقاً آخر بلا حالة خدمة أو موقع بعد',
      few: '$count سائقين آخرين بلا حالة خدمة أو موقع بعد',
      two: 'سائقان آخران بلا حالة خدمة أو موقع بعد',
      one: 'سائق آخر بلا حالة خدمة أو موقع بعد',
      zero: 'لا أحد غيرهم بلا حالة خدمة أو موقع',
    );
    return '$_temp0';
  }

  @override
  String get carrRidersNoPresenceNote =>
      'تظهر حالة خدمته وموقعه هنا بعد أن تربطه YouDrop بأسطولك — على أبعد تقدير بعد أول توصيل له لشركتك. وحتى ذلك الحين لا تستطيع هذه الصفحة معرفة ما إذا كان في الخدمة.';

  @override
  String get carrRidersVehicleModel => 'طراز المركبة';

  @override
  String get carrRidersPlateNumber => 'رقم اللوحة';

  @override
  String get carrRidersDateOfBirth => 'تاريخ الميلاد';

  @override
  String get carrRidersNationalIdNumber => 'رقم الهوية الوطنية';

  @override
  String get carrRidersDutyChanged => 'آخر تغيير لحالة الخدمة';

  @override
  String get carrRidersVehicleYear => 'سنة صنع المركبة';

  @override
  String get carrRidersTerminateReason => 'السبب، ويُحفظ في السجل';

  @override
  String get carrRidersTerminateReasonHint => 'لماذا ينتهي هذا العقد؟';

  @override
  String get carrRidersStatusStandingUnknown => 'الوضع غير معروف';

  @override
  String get carrRidersStandingUnknownNote =>
      'تعذّرت معرفة ما إذا كان هذا السائق موقوفاً حالياً، لذلك لا يُعرض الإيقاف ولا إعادة التفعيل. أعد تحميل الصفحة للمحاولة مجدداً.';

  @override
  String get attendanceBackToProfile => 'العودة إلى الملف الشخصي';

  @override
  String get blitzTitle => 'الكتالوج السريع';

  @override
  String get blitzSubtitle => 'كتالوجك من صور رفوفك';

  @override
  String get blitzFastSetup => 'إعداد سريع';

  @override
  String get blitzStepScan => 'صوّر المتجر';

  @override
  String get blitzStepCheck => 'راجع الأصناف';

  @override
  String get blitzStepSave => 'احفظ المسودات';

  @override
  String blitzStepDone(String step) {
    return '$step، مكتمل';
  }

  @override
  String blitzStepCurrent(String step) {
    return '$step، الخطوة الحالية';
  }

  @override
  String get blitzIntroTitle => 'صوّر رفوفك ووفّر على نفسك الكتابة';

  @override
  String get blitzIntroBody =>
      'التقط صورة لكل رف. نقرأ أسماء المنتجات وأحجامها ونقترح لكل منها قسماً وسعراً تقريبياً، وأنت تراجع كل صنف قبل حفظ أي شيء.';

  @override
  String get blitzTakePhoto => 'التقط صورة';

  @override
  String get blitzChoosePhotos => 'اختر صوراً';

  @override
  String blitzPhotoCount(int count, int max) {
    return 'الصور: $count من $max';
  }

  @override
  String blitzPhotoLabel(int number) {
    return 'صورة الرف $number';
  }

  @override
  String blitzUploading(int current, int total) {
    return 'جارٍ رفع الصورة $current من $total…';
  }

  @override
  String blitzScanPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'حلّل $count صورة',
      few: 'حلّل $count صور',
      two: 'حلّل صورتين',
      one: 'حلّل صورة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get blitzAnalyzing => 'نقرأ رفوفك…';

  @override
  String get blitzAnalyzingHint =>
      'قد يستغرق ذلك دقيقة أو دقيقتين. أبقِ هذه الشاشة مفتوحة.';

  @override
  String get blitzScanComplete => 'اكتمل التحليل';

  @override
  String blitzItemsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صنف',
      many: '$count صنفاً',
      few: '$count أصناف',
      two: 'صنفان',
      one: 'صنف واحد',
      zero: 'لا أصناف',
    );
    return '$_temp0';
  }

  @override
  String get blitzSampleTitle => 'أصناف تجريبية';

  @override
  String get blitzSampleBody =>
      'قارئ الصور غير مفعّل بعد، لذا هذه أصناف على سبيل المثال وليست ما على رفوفك. تجاوز أي صنف لا تبيعه.';

  @override
  String get blitzNoneFound => 'لم نتعرّف على أي منتج في هذه الصور.';

  @override
  String get blitzNoneFoundHint =>
      'جرّب صوراً أقرب تظهر فيها ملصقات المنتجات بوضوح.';

  @override
  String get blitzNewScan => 'ابدأ تحليلاً جديداً';

  @override
  String get blitzReviewCta => 'راجع واحفظ كمسودات';

  @override
  String get blitzFooter => 'لا يظهر شيء للزبائن قبل أن تنشره بنفسك.';

  @override
  String blitzScansLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تبقّى $count تحليل اليوم',
      many: 'تبقّى $count تحليلاً اليوم',
      few: 'تبقّت $count تحليلات اليوم',
      two: 'تبقّى تحليلان اليوم',
      one: 'تبقّى تحليل واحد اليوم',
      zero: 'لم يتبقَّ لك أي تحليل اليوم',
    );
    return '$_temp0';
  }

  @override
  String blitzQuotaReached(int limit) {
    return 'استخدمت كل التحليلات المتاحة لك اليوم ($limit). حاول مجدداً غداً.';
  }

  @override
  String get blitzFailedRefused =>
      'تعذّرت قراءة هذه الصور. جرّب صوراً واضحة لرفوف متجرك.';

  @override
  String get blitzFailedUnreadable =>
      'تعذّر فتح إحدى الصور. جرّب التقاطها من جديد.';

  @override
  String get blitzFailedProvider => 'لم يستجب قارئ الصور.';

  @override
  String get blitzFailedBusy =>
      'متاجر كثيرة تحلّل صورها الآن. حاول مجدداً بعد دقيقة.';

  @override
  String get blitzFailedInterrupted => 'توقّف التحليل قبل أن يكتمل.';

  @override
  String get blitzFailedOther => 'لم يكتمل التحليل.';

  @override
  String get blitzNoRetriesLeft =>
      'لا يمكن إعادة هذا التحليل. ابدأ تحليلاً جديداً.';

  @override
  String get blitzCameraFailed => 'لم تُفتح الكاميرا. اختر صورة بدلاً من ذلك.';

  @override
  String get blitzUploadFailed =>
      'لم تُرفع إحدى الصور. تحقّق من اتصالك وحاول مجدداً.';

  @override
  String get blitzCouldNotStart => 'تعذّر بدء التحليل.';

  @override
  String get blitzConnectionLost =>
      'تعذّر الاطلاع على حالة التحليل. تحقّق من اتصالك.';

  @override
  String blitzTag(String name, String price) {
    return '$name · حوالي $price';
  }

  @override
  String get blitzReviewTitle => 'راجع الأصناف';

  @override
  String get blitzReviewSubtitle => 'ما تبقيه يُحفظ كمسودة';

  @override
  String get blitzKeep => 'إبقاء';

  @override
  String blitzKeepItem(String name) {
    return 'إبقاء $name';
  }

  @override
  String get blitzName => 'الاسم';

  @override
  String get blitzPriceUsd => 'السعر (بالدولار)';

  @override
  String get blitzSection => 'القسم';

  @override
  String get blitzNoSection => 'بدون قسم';

  @override
  String blitzGuess(String price) {
    return 'تقدير: $price';
  }

  @override
  String get blitzUseGuess => 'استخدم هذا السعر';

  @override
  String get blitzCheckThis => 'لسنا متأكدين من هذا الصنف — تحقّق منه';

  @override
  String get blitzNeedName => 'أدخل اسماً';

  @override
  String get blitzNeedPrice => 'أدخل سعراً أكبر من صفر';

  @override
  String get blitzPriceDecimals => 'استخدم منزلتين عشريتين كحد أقصى';

  @override
  String blitzSaveDrafts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'احفظ $count مسودة',
      many: 'احفظ $count مسودة',
      few: 'احفظ $count مسودات',
      two: 'احفظ مسودتين',
      one: 'احفظ مسودة واحدة',
      zero: 'لا شيء للحفظ',
    );
    return '$_temp0';
  }

  @override
  String get blitzSkipAll => 'تجاوز كل الأصناف';

  @override
  String get blitzFixItems => 'أصلح الأصناف المعلَّمة أولاً.';

  @override
  String get blitzSavedTitle => 'حُفظت كمسودات';

  @override
  String blitzSavedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أُضيف $count منتج إلى كتالوجك كمسودات.',
      many: 'أُضيف $count منتجاً إلى كتالوجك كمسودات.',
      few: 'أُضيفت $count منتجات إلى كتالوجك كمسودات.',
      two: 'أُضيف منتجان إلى كتالوجك كمسودتين.',
      one: 'أُضيف منتج واحد إلى كتالوجك كمسودة.',
      zero: 'لم تُضف أي منتجات.',
    );
    return '$_temp0';
  }

  @override
  String get blitzSavedHint =>
      'تبقى المسودات مخفية عن الزبائن. أضف صورة لكل منها ثم انشرها من المخزون.';

  @override
  String get blitzDone => 'تم';

  @override
  String get blitzAlreadySaved => 'محفوظ';

  @override
  String blitzTooManyPhotos(int max) {
    return 'يتّسع التحليل الواحد لـ $max صور كحد أقصى، لذا لم تُضف الصور الزائدة.';
  }

  @override
  String get blitzSectionsUnavailable =>
      'تعذّر تحميل الأقسام، لذا يبقى لكل صنف القسم الذي اقترحناه.';

  @override
  String get blitzEntryAction => 'صوّر الرفوف';

  @override
  String get blitzSettingsRow => 'أنشئ الكتالوج من الصور';

  @override
  String get blitzSaveFailed => 'تعذّر الحفظ. تحقّق من اتصالك وحاول مرة أخرى.';

  @override
  String get blitzSavedEarlier => 'كانت هذه الأصناف قد حُفظت من قبل.';

  @override
  String get blitzListChanged =>
      'حُسم أمر بعض الأصناف في مكان آخر فخرجت من القائمة. راجع الباقي ثم احفظ مرة أخرى.';

  @override
  String get giftHubTitle => 'أرسل هدية';

  @override
  String get giftHubBannerTitle => 'الحوالة الحقيقية';

  @override
  String get giftHubBannerBody =>
      'ساند أحبّاءك في لبنان. اختر الأساسيات الحقيقية أو البقالة أو الوجبات الساخنة، وتصل إلى بابهم — غالباً في اليوم نفسه.';

  @override
  String get giftHowItWorks => 'كيف تعمل';

  @override
  String get giftStep1Title => 'اختر من المتاجر المحلية';

  @override
  String get giftStep1Body =>
      'اختر البقالة أو الحلويات أو منتجات الصيدلية أو سلة رعاية جاهزة.';

  @override
  String get giftStep2Title => 'أدخل عنوانهم في لبنان';

  @override
  String get giftStep2Body => 'نوصل إلى أي مكان يوصل إليه المتجر الذي تختاره.';

  @override
  String get giftStep3Title => 'توصيل في اليوم نفسه';

  @override
  String get giftStep3Body =>
      'يسلّمها السائق مع رسالتك الشخصية — في اليوم نفسه، ما دام المتجر مفتوحاً.';

  @override
  String get giftCategories => 'فئات الهدايا';

  @override
  String get giftCatCarePackage => 'سلة رعاية';

  @override
  String get giftCatGroceries => 'بقالة';

  @override
  String get giftCatMedicine => 'الدواء والصحة';

  @override
  String get giftRecentRecipients => 'المستلمون مؤخراً';

  @override
  String get giftAddRecipient => 'أضف مستلماً';

  @override
  String get giftFeaturedBundles => 'سلال رعاية مختارة';

  @override
  String get giftSameDayDeliverable => 'يصل في اليوم نفسه';

  @override
  String get giftHomeEntryTitle => 'أرسل هدية إلى لبنان';

  @override
  String get giftHomeEntrySub =>
      'بقالة وحلويات وسلال رعاية للعائلة، تصل إلى بابهم';

  @override
  String get giftDetailsTitle => 'تفاصيل الهدية';

  @override
  String get giftCheckoutSub => 'دفع المغتربين';

  @override
  String get giftRecipientInfo => 'معلومات المستلم';

  @override
  String get giftRecipientName => 'اسم المستلم';

  @override
  String get giftRecipientNameRequired => 'من سيستلمها؟';

  @override
  String get giftRecipientPhone => 'رقم الهاتف (لبنان)';

  @override
  String get giftPhoneInvalid => 'أدخل رقماً لبنانياً، مثل 71 234 567';

  @override
  String get giftDeliveryDate => 'تاريخ التوصيل';

  @override
  String get giftNoteTitle => 'أرفق رسالة شخصية';

  @override
  String get giftNoteHelper => 'يرسل المتجر رسالتك مع الهدية.';

  @override
  String get giftWrapTitle => 'تغليف هدايا فاخر';

  @override
  String giftWrapSubtitle(String amount) {
    return 'تغليف احتفالي مع رسالتك على بطاقة (+$amount)';
  }

  @override
  String get giftPaymentTitle => 'الدفع';

  @override
  String get giftCashNotAllowed =>
      'تُدفع الهدايا عبر الإنترنت — لا يُطلب من المستلم أن يدفع أبداً.';

  @override
  String get giftNoPaymentMethods =>
      'تُدفع الهدايا عبر الإنترنت، والدفع عبر الإنترنت غير مفعّل بعد — لذا لا يمكن إرسال هدية الآن.';

  @override
  String get giftTermsFailed => 'تعذّر تحميل خيارات الدفع للهدية.';

  @override
  String get giftOfflineCannotWait =>
      'لا يمكن للهدية انتظار عودة الاتصال كما يفعل الطلب النقدي، لأنها تُدفع عبر الإنترنت. أرسلها عند عودة الاتصال.';

  @override
  String get giftOrderSummary => 'ملخص الطلب';

  @override
  String giftLineQty(int qty, String name) {
    return '$qty× $name';
  }

  @override
  String get giftWrapLine => 'تغليف الهدية';

  @override
  String get giftDeliveryFee => 'رسوم التوصيل';

  @override
  String get giftTotalUsd => 'المجموع بالدولار';

  @override
  String giftApproxLbp(String amount) {
    return '≈ $amount';
  }

  @override
  String get giftTotalConfirmed => 'يُؤكَّد المجموع النهائي عند إرسال هديتك.';

  @override
  String get giftSendAndPay => 'أرسل الهدية وادفع';

  @override
  String giftForName(String name) {
    return 'هدية إلى $name';
  }

  @override
  String get giftWrapRequested => 'مطلوب تغليف الهدية';

  @override
  String get giftCardMessage => 'رسالة البطاقة';

  @override
  String get giftRecipientPhoneLabel => 'هاتف المستلم';

  @override
  String get giftBasketBanner => 'ترسل هذه السلة كهدية';

  @override
  String get giftBasketNotGift => 'ليست هدية';

  @override
  String get giftDeliveredToday => 'اليوم، خلال ساعات عمل المتجر';

  @override
  String giftNoteLength(int used, int max) {
    return '$used من $max';
  }

  @override
  String get giftUnnamed => 'هدية — يظهر اسم المستلم عندما تتولى توصيلها';

  @override
  String get heatmapTitle => 'رادار الطلب';

  @override
  String get heatmapSubtitle => 'نبض الأحياء لحظة بلحظة';

  @override
  String get heatmapActiveOrderDensities => 'كثافة الطلبات النشطة';

  @override
  String get heatmapLiveSyncing => 'مزامنة مباشرة';

  @override
  String get heatmapCantRefresh => 'تعذّر التحديث الآن';

  @override
  String get heatmapLevelHigh => 'مرتفع';

  @override
  String get heatmapLevelMedium => 'متوسط';

  @override
  String get heatmapLevelLow => 'منخفض';

  @override
  String heatmapZoneWithLevel(String zone, String level) {
    return '$zone ($level)';
  }

  @override
  String get heatmapWindowHour => 'آخر ساعة';

  @override
  String get heatmapWindowDay => 'آخر 24 ساعة';

  @override
  String get heatmapWindowWeek => 'آخر 7 أيام';

  @override
  String get heatmapAreasTitle => 'المناطق المحيطة بمتجرك';

  @override
  String get heatmapNotOnMap => 'غير محددة على الخريطة بعد';

  @override
  String get heatmapNoneOnMap => 'هذه المناطق غير محددة على الخريطة بعد';

  @override
  String get heatmapMapUnavailable => 'تعذّر تحميل الخريطة الآن';

  @override
  String get heatmapNoAreaTitle => 'لا نعرف حيّك بعد';

  @override
  String get heatmapNoAreaMessage =>
      'يظهر الطلب للمناطق المحددة على الخريطة قرب موقع متجرك. حدّد موقع متجرك إن لم تفعل بعد، وستظهر هنا المناطق القريبة فور إضافتها إلى الخريطة.';

  @override
  String get heatmapNotEnoughTitle => 'لا توجد طلبات كافية بالقرب منك بعد';

  @override
  String heatmapNotEnoughMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'تظهر المنطقة عندما يطلب منها $count عميل مختلف خلال هذه الفترة، فلا يمكن تمييز أي عميل بعينه.',
      many:
          'تظهر المنطقة عندما يطلب منها $count عميلاً مختلفاً خلال هذه الفترة، فلا يمكن تمييز أي عميل بعينه.',
      few:
          'تظهر المنطقة عندما يطلب منها $count عملاء مختلفين خلال هذه الفترة، فلا يمكن تمييز أي عميل بعينه.',
    );
    return '$_temp0';
  }

  @override
  String get heatmapCouldNotLoad => 'تعذّر تحميل الطلب الآن';

  @override
  String get heatmapNoShopMessage =>
      'سيظهر هنا الطلب من حول متجرك بعد إعداد متجرك.';

  @override
  String get heatmapEntryBlurb => 'اعرف أي الأحياء حول متجرك تطلب الآن';

  @override
  String get heatmapZoneCentreLatitude => 'خط العرض لمركز المنطقة (اختياري)';

  @override
  String get heatmapZoneCentreLongitude => 'خط الطول لمركز المنطقة (اختياري)';

  @override
  String get heatmapZoneCentreHelp =>
      'منتصف المنطقة تقريباً. يُظهر المنطقة على خريطة الطلب لدى التجار، ولا يدخل في التسعير.';

  @override
  String get heatmapZoneCentreBoth =>
      'أدخل القيمتين معاً أو اترك كلتيهما فارغتين';

  @override
  String get heatmapZoneCentreLatRange => 'خط عرض بين -90 و 90';

  @override
  String get heatmapZoneCentreLngRange => 'خط طول بين -180 و 180';

  @override
  String get heatmapZoneOnMap => 'على خريطة الطلب';

  @override
  String get heatmapZoneNotOnMap => 'ليست على خريطة الطلب';

  @override
  String get heatmapSubtitleDay => 'نبض الأحياء خلال آخر 24 ساعة';

  @override
  String get heatmapSubtitleWeek => 'نبض الأحياء خلال آخر 7 أيام';

  @override
  String get heatmapUpdatedHourly => 'يُحدَّث كل ساعة';

  @override
  String get heatmapUpdatedDaily => 'يُحدَّث مرة واحدة يومياً';

  @override
  String get heatmapLegendRelative => 'مقارنةً بأكثر منطقة طلباً من حولك';

  @override
  String get heatmapNotLiveTitle => 'متجرك غير منشور بعد';

  @override
  String get heatmapNotLiveMessage =>
      'سيظهر هنا الطلب من حول متجرك بعد نشر متجرك.';

  @override
  String get payrollNavLabel => 'الرواتب';

  @override
  String get payrollTitle => 'إدارة رواتب السائقين ومستحقاتهم';

  @override
  String get payrollSubtitle =>
      'اعتمد الدفعات، واحسب المكافآت، وتابع سجل الدفعات';

  @override
  String payrollPeriodLabel(String from, String to) {
    return 'فترة الرواتب: $from – $to';
  }

  @override
  String get payrollPeriodTooltip => 'اختر فترة الرواتب';

  @override
  String payrollPeriodOption(String from, String to, String state) {
    return '$from – $to · $state';
  }

  @override
  String get payrollRulesButton => 'قواعد الرواتب';

  @override
  String get payrollExport => 'تصدير كشوف الرواتب';

  @override
  String payrollExported(String file) {
    return 'تم حفظ $file.';
  }

  @override
  String get payrollStart => 'بدء دورة الرواتب';

  @override
  String get payrollRecompute => 'إعادة الحساب';

  @override
  String get payrollApprove => 'اعتماد دورة الرواتب';

  @override
  String get payrollPayAll => 'تسجيل كل الدفعات';

  @override
  String get payrollDiscard => 'تجاهل المسودة';

  @override
  String get payrollKpiPool => 'إجمالي الرواتب';

  @override
  String payrollKpiPoolNote(String from, String to) {
    return 'المستحق عن $from – $to';
  }

  @override
  String get payrollKpiRiders => 'السائقون في الرواتب';

  @override
  String payrollKpiRidersValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count سائق',
      many: '$count سائقاً',
      few: '$count سائقين',
      two: 'سائقان',
      one: 'سائق واحد',
      zero: 'لا سائقين',
    );
    return '$_temp0';
  }

  @override
  String get payrollKpiRidersNote => 'لديهم كشف راتب في هذه الفترة';

  @override
  String get payrollKpiAverage => 'متوسط مستحقات السائق';

  @override
  String payrollKpiAverageNote(int days) {
    return 'لكل فترة من $days يوماً';
  }

  @override
  String get payrollKpiBonuses => 'المكافآت';

  @override
  String get payrollKpiBonusesNote => 'المكافآت المسمّاة والتصحيحات';

  @override
  String get payrollLedgerTitle => 'سجل رواتب السائقين';

  @override
  String get payrollColRider => 'اسم السائق';

  @override
  String get payrollColBase => 'الأجر الأساسي';

  @override
  String get payrollColDelivery => 'أجر التوصيلات';

  @override
  String get payrollColTips => 'الإكراميات';

  @override
  String get payrollColDeductions => 'الاقتطاعات';

  @override
  String get payrollColGross => 'إجمالي الأجر';

  @override
  String get payrollColNet => 'صافي الأجر';

  @override
  String get payrollColStatus => 'الحالة';

  @override
  String get payrollColActions => 'الإجراءات';

  @override
  String get payrollPayslip => 'كشف الراتب';

  @override
  String get payrollTipsNote => 'الإكراميات ملك السائق ولا تدخل في أجره أبداً.';

  @override
  String get payrollHoursUnknown => 'تعذّرت قراءة ساعات هذا السائق.';

  @override
  String get payrollNobody => 'لا أحد من سائقي أسطولك لديه أجر في هذه الفترة.';

  @override
  String get payrollTableNote =>
      'هذه رواتب شركتك، محسوبة وفق قواعدك. لا تدفع YouDrop أجور سائقيك.';

  @override
  String get payrollStatusDraft => 'مسودة';

  @override
  String get payrollStatusDue => 'بانتظار الدفع';

  @override
  String get payrollStatusNothingDue => 'لا شيء للدفع';

  @override
  String get payrollStatusPaid => 'مدفوع ✓';

  @override
  String get payrollStatusFailed => 'فشل الدفع';

  @override
  String get payrollRunApproved => 'معتمدة';

  @override
  String get payrollRunPaid => 'مدفوعة';

  @override
  String get payrollNotStarted => 'لم تبدأ';

  @override
  String payrollRunMeta(String state, String time) {
    return '$state · حُسبت الأرقام في $time';
  }

  @override
  String payrollRunRevision(int revision) {
    return 'مسودة، النسخة $revision';
  }

  @override
  String payrollHoursAsOf(String time) {
    return 'الساعات كما قُرئت في $time';
  }

  @override
  String get payrollNoRulesTitle => 'حدّد قواعد الرواتب أولاً';

  @override
  String get payrollNoRulesBody =>
      'تحسب الرواتب أجر كل سائق وفق قواعد شركتك: كم تدفع عن التوصيلة، وهل تُدفع الساعات، وأي اقتطاعات. لا يُفترض شيء نيابةً عنك.';

  @override
  String get payrollNoRunTitle => 'لا توجد دورة رواتب لهذه الفترة بعد';

  @override
  String get payrollNoRunBody =>
      'بدء دورة يحسب مسودة من التوصيلات والساعات المسجّلة. لا شيء نهائي حتى تعتمدها.';

  @override
  String payrollPeriodOpen(String date) {
    return 'تستمر هذه الفترة حتى $date. يمكن اعتمادها بعد انتهائها.';
  }

  @override
  String get payrollHoursMissing =>
      'تعذّرت قراءة ساعات الحضور، لذا لا تتضمن هذه الأرقام أي ساعات.';

  @override
  String get payrollHoursNotDeployed =>
      'ساعات الحضور غير متاحة على هذه المنصة بعد، لذا لا تتضمن هذه الأرقام أي ساعات.';

  @override
  String get payrollHoursNotRead =>
      'أصبحت قواعد الرواتب تعتمد على الساعات. أعد الحساب لقراءتها.';

  @override
  String payrollJobsLateDraft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'وصلت $count توصيلة إلى السجل بعد حساب هذه الأرقام. أعد الحساب لتضمينها.',
      many:
          'وصلت $count توصيلة إلى السجل بعد حساب هذه الأرقام. أعد الحساب لتضمينها.',
      few:
          'وصلت $count توصيلات إلى السجل بعد حساب هذه الأرقام. أعد الحساب لتضمينها.',
      two:
          'وصلت توصيلتان إلى السجل بعد حساب هذه الأرقام. أعد الحساب لتضمينهما.',
      one:
          'وصلت توصيلة واحدة إلى السجل بعد حساب هذه الأرقام. أعد الحساب لتضمينها.',
    );
    return '$_temp0';
  }

  @override
  String payrollJobsLateApproved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'وصلت $count توصيلة من هذه الفترة إلى السجل بعد اعتمادها. أضف تصحيحات للسائقين المعنيين.',
      many:
          'وصلت $count توصيلة من هذه الفترة إلى السجل بعد اعتمادها. أضف تصحيحات للسائقين المعنيين.',
      few:
          'وصلت $count توصيلات من هذه الفترة إلى السجل بعد اعتمادها. أضف تصحيحات للسائقين المعنيين.',
      two:
          'وصلت توصيلتان من هذه الفترة إلى السجل بعد اعتمادها. أضف تصحيحات للسائقين المعنيين.',
      one:
          'وصلت توصيلة واحدة من هذه الفترة إلى السجل بعد اعتمادها. أضف تصحيحاً للسائق المعني.',
    );
    return '$_temp0';
  }

  @override
  String get payrollPeriodChanged =>
      'أصبحت قواعد الرواتب تدفع هذه الأيام ضمن فترة مختلفة. تجاهل هذه المسودة وابدأ تلك الفترة.';

  @override
  String get payrollLoadFailed => 'تعذّر تحميل الرواتب حالياً.';

  @override
  String get payrollTryAgain => 'حاول مجدداً';

  @override
  String payrollPayslipSubtitle(String from, String to) {
    return 'كشف الراتب عن $from – $to';
  }

  @override
  String get payrollSectionPay => 'الأجر';

  @override
  String get payrollSectionSummary => 'الملخص';

  @override
  String get payrollSectionAttendance => 'الساعات والحضور';

  @override
  String get payrollSectionPayment => 'الدفع';

  @override
  String payrollLineDeliveries(int count, String rate) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count توصيلة × $rate',
      many: '$count توصيلة × $rate',
      few: '$count توصيلات × $rate',
      two: 'توصيلتان × $rate',
      one: 'توصيلة واحدة × $rate',
      zero: 'لا توصيلات × $rate',
    );
    return '$_temp0';
  }

  @override
  String payrollLineHours(String hours, String rate) {
    return '$hours ساعة مسجّلة × $rate';
  }

  @override
  String payrollLineOvertime(String hours, String rate) {
    return '$hours ساعة إضافية × $rate';
  }

  @override
  String payrollLineTyped(String hours, String rate) {
    return '$hours ساعة أدخلها المكتب × $rate';
  }

  @override
  String payrollLineTypedUnpaid(String hours) {
    return '$hours ساعة أدخلها المكتب، لا تُدفع وفق قواعدك';
  }

  @override
  String payrollLineLate(int days, String rate) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days يوم تأخير × $rate',
      many: '$days يوم تأخير × $rate',
      few: '$days أيام تأخير × $rate',
      two: 'يوما تأخير × $rate',
      one: 'يوم تأخير واحد × $rate',
      zero: 'لا أيام تأخير × $rate',
    );
    return '$_temp0';
  }

  @override
  String payrollLineAbsence(int days, String rate) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days يوم غياب × $rate',
      many: '$days يوم غياب × $rate',
      few: '$days أيام غياب × $rate',
      two: 'يوما غياب × $rate',
      one: 'يوم غياب واحد × $rate',
      zero: 'لا أيام غياب × $rate',
    );
    return '$_temp0';
  }

  @override
  String get payrollLineCash =>
      'نقد الشركة الذي كان بحوزة السائق، مقتطع من الأجر';

  @override
  String payrollLineBonus(String label) {
    return 'مكافأة: $label';
  }

  @override
  String payrollLineDeduction(String label) {
    return 'اقتطاع: $label';
  }

  @override
  String payrollLineCorrection(String label) {
    return 'تصحيح: $label';
  }

  @override
  String get payrollLineOther => 'أخرى';

  @override
  String payrollOwes(String amount) {
    return 'مدين للشركة بمبلغ $amount. لا يُدفع له شيء.';
  }

  @override
  String payrollTipsInfo(String amount) {
    return 'إكراميات $amount: ملك السائق، وليست جزءاً من هذا الأجر.';
  }

  @override
  String payrollCashKept(String amount, String date) {
    return 'يحتفظ بمبلغ $amount من نقد الشركة جمعه حتى $date، وهو أكثر مما يغطيه هذا الأجر. يبقى ليُستلم في المركز.';
  }

  @override
  String payrollHoursFacts(String recorded, String typed, String overtime) {
    return 'مسجّلة $recorded س · مُدخلة $typed س · إضافية $overtime س';
  }

  @override
  String payrollDaysFacts(int lates, int absences) {
    return 'أيام التأخير $lates · أيام الغياب $absences';
  }

  @override
  String get payrollAddBonus => 'إضافة مكافأة';

  @override
  String get payrollAddDeduction => 'إضافة اقتطاع';

  @override
  String get payrollRemove => 'إزالة';

  @override
  String get payrollMarkPaid => 'تسجيل الدفع';

  @override
  String get payrollMarkFailed => 'تسجيل فشل الدفع';

  @override
  String get payrollAddCorrection => 'إضافة تصحيح';

  @override
  String payrollPaidOn(String date, String method) {
    return 'دُفع في $date · $method';
  }

  @override
  String payrollRecordedBy(String name) {
    return 'سجّله $name';
  }

  @override
  String payrollFailedBecause(String reason) {
    return 'فشل الدفع: $reason';
  }

  @override
  String get payrollCorrections => 'التصحيحات';

  @override
  String get payrollCorrectionWaiting => 'تُدفع في دورة الرواتب التالية للسائق';

  @override
  String get payrollCorrectionPaid => 'دُفعت في دورة رواتب لاحقة';

  @override
  String payrollLineDialogBonus(String name) {
    return 'إضافة مكافأة لـ$name';
  }

  @override
  String payrollLineDialogDeduction(String name) {
    return 'إضافة اقتطاع من أجر $name';
  }

  @override
  String get payrollLabelField => 'سببها';

  @override
  String get payrollAmountField => 'المبلغ';

  @override
  String get payrollAmountInvalid => 'مبلغ حتى السنت، مثل 25.00';

  @override
  String get payrollRequired => 'مطلوب';

  @override
  String get payrollReasonField => 'السبب';

  @override
  String get payrollReferenceField => 'المرجع (اختياري)';

  @override
  String get payrollSave => 'حفظ';

  @override
  String payrollCorrectionTitle(String name) {
    return 'تصحيح أجر $name';
  }

  @override
  String get payrollCorrectionBody =>
      'يبقى كشف الراتب المعتمد كما هو. يُدفع التصحيح في دورة الرواتب التالية للسائق.';

  @override
  String get payrollCorrectionMore => 'دفع مبلغ إضافي';

  @override
  String get payrollCorrectionLess => 'استرداد مبلغ';

  @override
  String payrollFailedTitle(String name) {
    return 'لم يصل الدفع إلى $name؟';
  }

  @override
  String get payrollFailedBody => 'يبقى الأجر مستحقاً ويمكن تسجيل دفعه لاحقاً.';

  @override
  String payrollPaidTitle(String name, String amount) {
    return 'تسجيل دفع $amount إلى $name؟';
  }

  @override
  String get payrollPaidBody =>
      'يسجّل هذا أن شركتك دفعت للسائق. لا تحوّل YouDrop أي أموال.';

  @override
  String payrollApproveTitle(String from, String to) {
    return 'اعتماد الرواتب عن $from – $to؟';
  }

  @override
  String payrollApproveBody(int count, String total) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count سائق، والمستحق $total. تصبح كشوف الرواتب نهائية بعد الاعتماد، ويُصحَّح أي خطأ في دورة لاحقة.',
      many:
          '$count سائقاً، والمستحق $total. تصبح كشوف الرواتب نهائية بعد الاعتماد، ويُصحَّح أي خطأ في دورة لاحقة.',
      few:
          '$count سائقين، والمستحق $total. تصبح كشوف الرواتب نهائية بعد الاعتماد، ويُصحَّح أي خطأ في دورة لاحقة.',
      two:
          'سائقان، والمستحق $total. تصبح كشوف الرواتب نهائية بعد الاعتماد، ويُصحَّح أي خطأ في دورة لاحقة.',
      one:
          'سائق واحد، والمستحق $total. تصبح كشوف الرواتب نهائية بعد الاعتماد، ويُصحَّح أي خطأ في دورة لاحقة.',
    );
    return '$_temp0';
  }

  @override
  String payrollApproveCash(String amount, String date) {
    return 'يُقتطع من أجور سائقيك $amount من نقد الشركة الذي جمعوه حتى $date وما زال بحوزتهم، ويُسجَّل على أنه سُلِّم إلى شركتك.';
  }

  @override
  String get payrollApproveYes => 'اعتماد';

  @override
  String payrollPayAllTitle(int count, String total) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تسجيل $count دفعة بمجموع $total؟',
      many: 'تسجيل $count دفعة بمجموع $total؟',
      few: 'تسجيل $count دفعات بمجموع $total؟',
      two: 'تسجيل دفعتين بمجموع $total؟',
      one: 'تسجيل دفعة واحدة بقيمة $total؟',
    );
    return '$_temp0';
  }

  @override
  String get payrollPayAllBody =>
      'يسجّل هذا أن شركتك دفعت لهؤلاء السائقين، ولا يمكن التراجع عنه. تُترك الدفعات الفاشلة لتُسجَّل واحدة تلو الأخرى.';

  @override
  String get payrollRecordYes => 'تسجيل';

  @override
  String get payrollDiscardTitle => 'تجاهل هذه المسودة؟';

  @override
  String get payrollDiscardBody =>
      'تُحذف أرقامها ويُحتفظ بسجلها. يمكنك بدء الفترة من جديد.';

  @override
  String get payrollDiscardYes => 'تجاهل';

  @override
  String get payrollDone => 'تم الحفظ.';

  @override
  String get payrollApproved => 'اعتُمدت دورة الرواتب.';

  @override
  String get payrollErrFiguresChanged =>
      'تغيّرت الأرقام منذ اطّلعت عليها. راجع الأرقام الجديدة ثم اعتمد مجدداً.';

  @override
  String get payrollErrCashChanged =>
      'تغيّر نقد أحد السائقين للتو. لم يُعتمد شيء؛ اعتمد مجدداً لترى الأرقام الجديدة.';

  @override
  String payrollErrTotalChanged(String amount) {
    return 'أصبح المجموع المنتظر للدفع $amount. لم يُسجَّل شيء.';
  }

  @override
  String get payrollErrRefused =>
      'تعذّر ذلك: تغيّرت دورة الرواتب أو لم تعد تسمح به. أعد التحميل وحاول مجدداً.';

  @override
  String get payrollErrFailed => 'تعذّر ذلك حالياً. يُرجى المحاولة مجدداً.';

  @override
  String get payrollErrRulesStart =>
      'لا يمكن أن تبدأ القواعد الجديدة في ذلك اليوم. اختر أحد الأيام المتاحة.';

  @override
  String payrollRulesNow(String from) {
    return 'سارية منذ $from';
  }

  @override
  String get payrollRulesNone => 'لا توجد قواعد رواتب بعد.';

  @override
  String payrollRulesNext(String date) {
    return 'تبدأ قواعد جديدة في $date';
  }

  @override
  String get payrollRulesCycle => 'دورية الدفع';

  @override
  String get payrollCycleSemiMonthly => 'مرتين شهرياً (1–15، و16–نهاية الشهر)';

  @override
  String get payrollCycleMonthly => 'شهرياً';

  @override
  String get payrollRulesStart => 'ابتداءً من';

  @override
  String get payrollRulesPerDelivery => 'الأجر عن كل توصيلة';

  @override
  String get payrollRulesHourly => 'أجر الساعة (اختياري)';

  @override
  String get payrollRulesHourlyHint =>
      'اتركه فارغاً إن لم يكن هناك أجر بالساعة';

  @override
  String get payrollRulesTyped => 'دفع الساعات التي يُدخلها المكتب';

  @override
  String get payrollRulesOvertime => 'مضاعِف الساعات الإضافية';

  @override
  String get payrollRulesLate => 'الاقتطاع عن كل يوم تأخير';

  @override
  String get payrollRulesAbsence => 'الاقتطاع عن كل يوم غياب';

  @override
  String get payrollRulesSave => 'حفظ القواعد';

  @override
  String get payrollRulesNote =>
      'تسري القواعد من أول يوم في فترة الرواتب، ولا تغيّر أي دورة رواتب معتمدة.';

  @override
  String get payrollMultiplierInvalid => 'بين 1.00 و5.00';

  @override
  String get payrollRulesNoStart => 'لا يوجد يوم متاح لقواعد جديدة حالياً.';

  @override
  String get payrollCashMethodKeptFromPay => 'مقتطع من الأجر';

  @override
  String payrollReadBeforeEnd(String time) {
    return 'قُرئت هذه الأرقام في $time، قبل انتهاء الفترة. أعد الحساب لاحتساب الفترة كاملة قبل الاعتماد.';
  }

  @override
  String get payrollDeliveriesNotDeployed =>
      'لا يمكن بعدُ احتساب التوصيلات من الطلبات على هذه المنصة، لذا لا تحتسب هذه الأرقام إلا التوصيلات التي حقّقت أجرة، وتنقصها التوصيلات المجانية.';

  @override
  String get payrollDeliveriesMissing =>
      'تعذّر احتساب التوصيلات من الطلبات حالياً، لذا لا تحتسب هذه الأرقام إلا التوصيلات التي حقّقت أجرة. أعد الحساب لاحتساب كل التوصيلات.';

  @override
  String payrollHoursMissingFor(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تعذّرت قراءة ساعات $names، لذا لا يتضمن أجرهم أي ساعات.',
      many: 'تعذّرت قراءة ساعات $names، لذا لا يتضمن أجرهم أي ساعات.',
      few: 'تعذّرت قراءة ساعات $names، لذا لا يتضمن أجرهم أي ساعات.',
      two: 'تعذّرت قراءة ساعات $names، لذا لا يتضمن أجرهما أي ساعات.',
      one: 'تعذّرت قراءة ساعات $names، لذا لا يتضمن أجره أي ساعات.',
    );
    return '$_temp0';
  }

  @override
  String payrollNamesMore(String names, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$names و$count سائق آخر',
      many: '$names و$count سائقاً آخر',
      few: '$names و$count سائقين آخرين',
      two: '$names وسائقان آخران',
      one: '$names وسائق آخر',
    );
    return '$_temp0';
  }

  @override
  String get payrollListSeparator => '، ';

  @override
  String get payrollApproveDeliveriesLedger =>
      'احتُسبت التوصيلات من المهام التي حقّقت أجرة فقط، لذا تنقص التوصيلات المجانية من هذا الأجر.';

  @override
  String get payrollApproveWithoutMissing => 'الاعتماد من دون ما ينقص';

  @override
  String get payrollErrNeedsAcknowledgement =>
      'تنقص هذه الأرقام بعض المعطيات. حدّد الخانة للاعتماد من دونها.';

  @override
  String get payrollErrRecomputeNeeded =>
      'قُرئت هذه الأرقام قبل انتهاء الفترة. أعد الحساب وراجع الأرقام ثم اعتمد مجدداً.';

  @override
  String get payrollHoursNotListed =>
      'لا يُظهر الحضور أي وقت عمل فيه هذا السائق لشركتك خلال هذه الفترة، لذا ساعاته غير معروفة.';

  @override
  String get chatRoomEntryTitle => 'دردشة الحي';

  @override
  String get chatRoomEntrySub => 'تحدّث مع الناس الذين يسكنون حولك';

  @override
  String chatRoomTitle(String area) {
    return 'دردشة $area';
  }

  @override
  String get chatRoomLive => 'مباشر';

  @override
  String chatRoomMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count جار',
      many: '$count جاراً',
      few: '$count جيران',
      two: 'جاران',
      one: 'جار واحد',
      zero: 'لا جيران',
    );
    return '$_temp0';
  }

  @override
  String get chatRoomCommunity => 'المجتمع';

  @override
  String get chatRoomComposerHint => 'اكتب رسالة أو اسأل جارك…';

  @override
  String get chatRoomEmpty => 'لا رسائل بعد. ألقِ التحية على جيرانك.';

  @override
  String get chatRoomCouldNotLoad => 'تعذّر تحميل دردشة الحي';

  @override
  String get chatRoomPickAreaTitle => 'اختر منطقتك لتنضمّ إلى دردشتها';

  @override
  String get chatRoomPickAreaBody =>
      'تتبع دردشة الحي منطقة عنوان التوصيل الخاص بك.';

  @override
  String get chatRoomChooseArea => 'اختر المنطقة';

  @override
  String get chatRoomUnknownAreaTitle => 'لا توجد دردشة حي لمنطقتك';

  @override
  String get chatRoomUnknownAreaBody =>
      'اختر إحدى مناطق التوصيل لعنوانك لتنضمّ إلى دردشتها.';

  @override
  String chatRoomMoveBlocked(String date) {
    return 'يمكنك الانتقال إلى دردشة منطقتك الجديدة ابتداءً من $date.';
  }

  @override
  String chatRoomMuted(String date) {
    return 'أوقف أحد المشرفين رسائلك هنا حتى $date.';
  }

  @override
  String get chatRoomHidden => 'أُزيلت هذه الرسالة';

  @override
  String get chatRoomNeighbour => 'جار';

  @override
  String get chatRoomReport => 'إبلاغ';

  @override
  String get chatRoomReportTitle => 'لماذا تبلّغ عن هذه الرسالة؟';

  @override
  String get chatRoomReasonSpam => 'رسائل مزعجة أو إعلانات';

  @override
  String get chatRoomReasonAbuse => 'إساءة أو مضايقة';

  @override
  String get chatRoomReasonPersonalInfo => 'معلومات شخصية لأحدهم';

  @override
  String get chatRoomReasonOther => 'سبب آخر';

  @override
  String get chatRoomReportSent => 'شكراً. سيراجعها أحد المشرفين.';

  @override
  String get chatRoomBlock => 'حظر';

  @override
  String chatRoomBlockTitle(String name) {
    return 'حظر $name؟';
  }

  @override
  String get chatRoomBlockBody =>
      'لن ترى رسائله في دردشة الحي، ولن يُبلَّغ بذلك.';

  @override
  String get chatRoomBlockedToast => 'تم الحظر. لن ترى رسائله.';

  @override
  String get chatRoomCopy => 'نسخ';

  @override
  String get chatRoomCopied => 'تم النسخ';

  @override
  String get chatRoomRulesTitle => 'قواعد المجتمع';

  @override
  String get chatRoomRulesBody =>
      'كن لطيفاً مع جيرانك. لا رسائل مزعجة أو إعلانات، ولا مضايقات، ولا تنشر أبداً رقم هاتف أحد أو عنوانه. يزيل المشرفون الرسائل التي تخالف هذه القواعد.';

  @override
  String get chatRoomBlockedPeople => 'الأشخاص الذين حظرتهم';

  @override
  String get chatRoomNoBlocks => 'لم تحظر أحداً.';

  @override
  String get chatRoomUnblock => 'إلغاء الحظر';

  @override
  String get chatSlowDown =>
      'ترسل الرسائل بسرعة كبيرة. انتظر قليلاً ثم حاول مجدداً.';

  @override
  String get chatTooLong => 'هذه الرسالة طويلة جداً.';

  @override
  String get chatActionFailed => 'لم ينجح ذلك. حاول مجدداً.';

  @override
  String chatShopWith(String shop) {
    return 'دردش مع $shop';
  }

  @override
  String get chatShopHintCustomer => 'راسل المحل…';

  @override
  String get chatShopHintMerchant => 'ردّ على الزبون…';

  @override
  String get chatShopEmptyCustomer =>
      'اسأل المحل عن أي شيء: البضاعة المتوفرة، الأسعار، مواعيد العمل.';

  @override
  String get chatShopEmptyMerchant => 'لا رسائل في هذه المحادثة بعد.';

  @override
  String get chatShopCouldNotLoad => 'تعذّر تحميل هذه المحادثة';

  @override
  String get chatShopQuietCustomer => 'هدأت هذه المحادثة.';

  @override
  String get chatShopReopen => 'إعادة فتح';

  @override
  String get chatShopQuietMerchant =>
      'هدأت هذه المحادثة. يستطيع الزبون استئنافها من صفحة محلك.';

  @override
  String get chatShopInboxTitle => 'رسائل الزبائن';

  @override
  String get chatShopInboxEmpty => 'لا رسائل من الزبائن بعد';

  @override
  String get chatShopInboxEmptySub =>
      'يستطيع الزبائن مراسلة محلك من صفحته في التطبيق.';

  @override
  String get chatShopInboxCouldNotLoad => 'تعذّر تحميل رسائل الزبائن';

  @override
  String get chatShopCustomer => 'زبون';

  @override
  String chatShopYouPrefix(String text) {
    return 'أنت: $text';
  }

  @override
  String get chatShopQuietBadge => 'هادئة';

  @override
  String get chatModerationTitle => 'الإشراف';

  @override
  String get chatModerationSub =>
      'رسائل دردشة الحي المُبلَّغ عنها، الأقدم أولاً.';

  @override
  String get chatModerationEmpty => 'لا بلاغات بانتظار المراجعة';

  @override
  String get chatModerationCouldNotLoad => 'تعذّر تحميل قائمة الإشراف';

  @override
  String chatModerationReports(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count بلاغ',
      many: '$count بلاغاً',
      few: '$count بلاغات',
      two: 'بلاغان',
      one: 'بلاغ واحد',
      zero: 'لا بلاغات',
    );
    return '$_temp0';
  }

  @override
  String get chatModerationHide => 'إخفاء الرسالة';

  @override
  String get chatModerationDismiss => 'تجاهل';

  @override
  String get chatModerationMute => 'كتم الكاتب';

  @override
  String get chatModerationUnmute => 'إلغاء كتم الكاتب';

  @override
  String get chatModerationMute24h => 'لمدة 24 ساعة';

  @override
  String get chatModerationMute7d => 'لمدة 7 أيام';

  @override
  String get chatModerationMute30d => 'لمدة 30 يوماً';

  @override
  String get chatModerationReasonLabel => 'السبب (يُحفظ في سجل التدقيق)';

  @override
  String get chatModerationReasonTooShort => 'اكتب 3 أحرف على الأقل';

  @override
  String get chatModerationConfirm => 'تأكيد';

  @override
  String get chatModerationRemoved => 'أُزيلت';

  @override
  String chatModerationMutedUntil(String date) {
    return 'الكاتب مكتوم حتى $date';
  }

  @override
  String get chatModerationDone => 'تم';

  @override
  String get chatModerationRefresh => 'تحديث';

  @override
  String get chatRoomOlderFailed =>
      'تعذّر تحميل الرسائل الأقدم. اضغط للمحاولة مجدداً.';

  @override
  String get chatRoomPostAfterDelivery =>
      'يمكنك الكتابة هنا بعد أول توصيل لك إلى هذه المنطقة.';

  @override
  String get chatRoomPostingUnavailable =>
      'الكتابة متوقفة مؤقتاً ريثما نتحقق من طلباتك. حاول مجدداً بعد قليل.';

  @override
  String chatShopUnreadCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count رسالة غير مقروءة',
      many: '$count رسالة غير مقروءة',
      few: '$count رسائل غير مقروءة',
      two: 'رسالتان غير مقروءتين',
      one: 'رسالة واحدة غير مقروءة',
      zero: 'لا رسائل غير مقروءة',
    );
    return '$_temp0';
  }

  @override
  String get multiCartTitle => 'السلة الذكية';

  @override
  String get multiCartSubtitle => 'دفعة واحدة لكل المتاجر';

  @override
  String multiCartShopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count متجر',
      many: '$count متجرًا',
      few: '$count متاجر',
      two: 'متجران',
      one: 'متجر واحد',
    );
    return '$_temp0';
  }

  @override
  String multiCartFromShop(int count, String store) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'من $store ($count صنف)',
      many: 'من $store ($count صنفًا)',
      few: 'من $store ($count أصناف)',
      two: 'من $store (صنفان)',
      one: 'من $store (صنف واحد)',
    );
    return '$_temp0';
  }

  @override
  String get multiCartShopDelivery => 'التوصيل من هذا المتجر';

  @override
  String multiCartDeliveryFromShops(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'التوصيل من $count متجر',
      many: 'التوصيل من $count متجرًا',
      few: 'التوصيل من $count متاجر',
      two: 'التوصيل من متجرين',
      one: 'التوصيل من متجر واحد',
    );
    return '$_temp0';
  }

  @override
  String multiCartCheckoutAmount(String amount) {
    return 'إتمام الطلب — $amount';
  }

  @override
  String multiCartBelowMinimum(String amount, String store) {
    return 'أضف $amount من $store لبلوغ الحد الأدنى للطلب';
  }

  @override
  String multiCartShopClosed(String store) {
    return '$store مغلق الآن. أزل منتجاته لإتمام الطلب.';
  }

  @override
  String multiCartShopNotServing(String store) {
    return '$store لا يوصّل إلى عنوانك. أزل منتجاته لإتمام الطلب.';
  }

  @override
  String multiCartShopUnavailable(String store) {
    return 'لا يستطيع $store استلام هذا الطلب الآن.';
  }

  @override
  String multiCartRemoveShop(String store) {
    return 'إزالة $store';
  }

  @override
  String multiCartShopLimitTitle(int max) {
    String _temp0 = intl.Intl.pluralLogic(
      max,
      locale: localeName,
      other: 'حتى $max متجر في السلة',
      many: 'حتى $max متجرًا في السلة',
      few: 'حتى $max متاجر في السلة',
      two: 'حتى متجرين في السلة',
      one: 'متجر واحد في السلة',
    );
    return '$_temp0';
  }

  @override
  String get multiCartShopLimitBody =>
      'أتمّ طلبك أو أزل متجرًا من سلتك قبل إضافة منتجات من متجر آخر.';

  @override
  String multiCartPartOfOrder(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'جزء من طلب من $count متجر',
      many: 'جزء من طلب من $count متجرًا',
      few: 'جزء من طلب من $count متاجر',
      two: 'جزء من طلب من متجرين',
    );
    return '$_temp0';
  }

  @override
  String get multiCartCannotWait =>
      'لا يمكن لسلة من عدة متاجر أن تنتظر عودة الاتصال: تُرسل طلبات متاجرها معًا وأنت متصل. أتمّ الطلب عند عودة الاتصال.';

  @override
  String get multiCartGiftOneShop =>
      'تُرسل الهدية من متجر واحد في كل مرة. أزل منتجات المتاجر الأخرى، أو أرسل هذه السلة كطلب عادي.';

  @override
  String multiCartPlaced(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم إرسال $count طلب · $amount',
      many: 'تم إرسال $count طلبًا · $amount',
      few: 'تم إرسال $count طلبات · $amount',
      two: 'تم إرسال طلبين · $amount',
      one: 'تم إرسال طلب واحد · $amount',
    );
    return '$_temp0';
  }

  @override
  String get multiCartPricesUpdating => 'جارٍ تحديث الأسعار…';

  @override
  String get multiCartPricesFailed => 'تعذّر تأكيد أحدث الأسعار.';

  @override
  String get multiCartPriceChangedTitle => 'تغيّر المجموع';

  @override
  String multiCartPriceChangedBody(String total, String agreed) {
    return 'أصبح مجموع سلتك $total بدلًا من $agreed الذي رأيته. هل تريد إتمام طلباتها بالمجموع الجديد؟';
  }

  @override
  String multiCartEarlierCheckoutPlaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'نجحت محاولتك السابقة بالفعل: الطلبات الـ$count كلها في «الطلبات».',
      many: 'نجحت محاولتك السابقة بالفعل: الطلبات الـ$count كلها في «الطلبات».',
      few: 'نجحت محاولتك السابقة بالفعل: الطلبات الـ$count كلها في «الطلبات».',
      two: 'نجحت محاولتك السابقة بالفعل: الطلبان كلاهما في «الطلبات».',
    );
    return '$_temp0';
  }

  @override
  String get svcVerticalServices => 'خدمات';

  @override
  String get svcCategoryPrinting => 'طباعة';

  @override
  String get svcCategoryTailoring => 'خياطة وتعديل ملابس';

  @override
  String get svcCategoryRepairs => 'تصليحات';

  @override
  String get svcCategoryPhotography => 'تصوير';

  @override
  String get svcCategoryCleaning => 'تنظيف';

  @override
  String get svcCategoryBeauty => 'تجميل';

  @override
  String get svcCategoryTutoring => 'دروس خصوصية';

  @override
  String get svcSignupTitle => 'كبّر عملك مع YouDrop';

  @override
  String get svcSignupSubtitle => 'اوصل إلى الزبائن في منطقتك.';

  @override
  String get svcSignupBannerTitle => 'خدمات لبنانية';

  @override
  String get svcSignupBannerBody =>
      'طباعة، خياطة، تصليحات، تصوير والمزيد — يستلمها الزبون من محلّك أو يوصلها YouDrop.';

  @override
  String get svcBusinessName => 'اسم العمل';

  @override
  String get svcBusinessNameHint => 'مثلاً: مطبعة الفاخوري';

  @override
  String get svcServiceCategory => 'فئة الخدمة';

  @override
  String get svcServiceCategoryHint => 'اختر ما تقدّمه';

  @override
  String get svcPhoneHint => '71 234 567';

  @override
  String get svcPhoneInvalid => 'أدخل رقماً لبنانياً، مثل 71 234 567';

  @override
  String get svcArea => 'الموقع / المنطقة';

  @override
  String get svcAreaHint => 'اختر منطقتك';

  @override
  String get svcApplyCta => 'قدّم طلب بيع الخدمات';

  @override
  String get svcOptionsFailed =>
      'تعذّر تحميل الخدمات المتاحة. تحقّق من اتصالك وحاول مجدداً.';

  @override
  String get svcNoCategoriesOpen =>
      'لا يستقبل YouDrop طلبات لبيع الخدمات حالياً.';

  @override
  String get svcPendingTitle => 'تم إرسال طلبك';

  @override
  String svcPendingBody(String email) {
    return 'يقرأ فريق YouDrop كل طلب لبيع الخدمات. سنراسلك على $email عند اتخاذ القرار.';
  }

  @override
  String get svcPendingBodyNoEmail =>
      'يقرأ فريق YouDrop كل طلب لبيع الخدمات، وسنبلغك عند اتخاذ القرار.';

  @override
  String svcReference(String reference) {
    return 'المرجع: $reference';
  }

  @override
  String get svcApprovedTitle => 'تمت الموافقة على طلبك';

  @override
  String get svcApprovedBody => 'نفتح محلّ خدماتك في أول مرة تدخل إليه.';

  @override
  String get svcErrCategoryClosed =>
      'لا يستقبل YouDrop طلبات لهذه الخدمة بعد. اختر خدمة أخرى.';

  @override
  String get svcErrCategoryMissing => 'اختر الخدمة التي تقدّمها.';

  @override
  String get svcErrAreaUnknown =>
      'لم تعد هذه المنطقة على القائمة. اختر منطقتك من جديد.';

  @override
  String get svcErrAreaMissing => 'اختر المنطقة التي يقع فيها عملك.';

  @override
  String get svcErrCatalogUnavailable =>
      'تعذّر التحقق من الخدمات المتاحة الآن. حاول بعد قليل.';

  @override
  String get svcOfferYourServices => 'قدّم خدماتك';

  @override
  String get svcOfferYourServicesSub => 'طباعة، خياطة، تصليحات أو تصوير';

  @override
  String get svcSwitchToShop => 'انتقل إلى محلّك';

  @override
  String get svcSwitchToShopping => 'انتقل إلى التسوّق';

  @override
  String get svcChoiceCard => 'قدّم خدمات';

  @override
  String get svcChoiceCardBlurb =>
      'اطبع أو خيّط أو صلّح أو صوّر لزبائن منطقتك، من محلّك.';

  @override
  String get svcIntent => 'خدمات';

  @override
  String get svcIntentBlurb => 'أطبع أو أخيّط أو أصلّح أو أصوّر';

  @override
  String get svcOpeningShop => 'نفتح محلّ خدماتك…';

  @override
  String get svcOpeningShopFailed => 'تعذّر فتح محلّ خدماتك.';

  @override
  String get svcDocsTitle => 'أضف مستنداتك';

  @override
  String get svcDocsIntro =>
      'تساعد بطاقة هويتك وسجلّك التجاري فريق المراجعة على اتخاذ القرار. أرسل صوراً واضحة أو ملفات PDF.';

  @override
  String get svcDocsFootnote =>
      'تصل المستندات إلى فريق المراجعة عند الضغط على «أرسل المستندات».';

  @override
  String get svcDocsSend => 'أرسل المستندات';

  @override
  String get svcDocsSent => 'مستنداتك لدى فريق المراجعة.';

  @override
  String get svcDocsSkipped =>
      'لم تُرسل أي مستندات، لذا سيرى فريق المراجعة أن بطاقة هويتك وسجلّك التجاري غير مرفقين.';

  @override
  String get svcShopCategoryClosedTitle => 'خدمتك غير متاحة حالياً';

  @override
  String get svcShopCategoryClosedBody =>
      'تمت الموافقة على طلبك، لكن YouDrop لا يقدّم هذه الخدمة حالياً، لذا لا يمكن فتح محلّك. يُرجى التواصل مع الدعم.';

  @override
  String svcCashShopName(String id) {
    return 'المتجر $id';
  }

  @override
  String svcCashShopTakenAtCounter(String amount) {
    return '$amount دفعها الزبائن على صندوقه';
  }

  @override
  String svcCashShopConfirmBody(
      String shop, String owed, String held, String orders) {
    return 'أكّد أنّ $shop دفع للمنصة $owed: عمولتها من $held دفعها زبائنه على صندوقه، عن $orders. يحتفظ المتجر بالباقي حصةً له. لا يمكن التراجع عن ذلك.';
  }

  @override
  String svcCashShopAmountChanged(String shop, String amount) {
    return '$shop مدين الآن بـ $amount، وليس بالمبلغ الذي أكّدته. لم يُسجَّل شيء.';
  }

  @override
  String get svcActionCollected => 'استلمه الزبون';

  @override
  String get svcDeclineTooBusy => 'مشغولون جدًا الآن';

  @override
  String get svcDeclineCannotDo => 'لا يمكننا تنفيذ هذا العمل';

  @override
  String get svcDeclineFileProblem => 'مشكلة في الملف';

  @override
  String get svcDeclineOther => 'سبب آخر';

  @override
  String get svcNavServices => 'الخدمات';

  @override
  String get svcBrandPill => 'خدمات يودروب';

  @override
  String get svcSearchHint => 'ابحث عن خدمة…';

  @override
  String get svcCategoriesTitle => 'فئات الخدمات';

  @override
  String get svcPopularNearYou => 'خدمات رائجة بالقرب منك';

  @override
  String get svcNearYou => 'خدمات بالقرب منك';

  @override
  String get svcAllProviders => 'مقدّمو الخدمات';

  @override
  String get svcNoServicesNearby => 'لا توجد خدمات بالقرب منك بعد';

  @override
  String get svcNoServicesNearbyHint =>
      'جرّب إحدى الفئات، أو ابحث عمّا تحتاجه.';

  @override
  String get svcServicesNotOffered => 'لا تقدّم يودروب خدمات هنا بعد';

  @override
  String get svcCouldNotLoadServices => 'تعذّر تحميل الخدمات';

  @override
  String svcDistanceAway(String distance) {
    return 'على بُعد $distance';
  }

  @override
  String get svcOffers => 'العروض';

  @override
  String get svcSearchProviders => 'مقدّمو الخدمات';

  @override
  String svcSearchTitle(String query) {
    return 'نتائج «$query»';
  }

  @override
  String svcNoResults(String query) {
    return 'لم نجد شيئًا لـ«$query»';
  }

  @override
  String svcCategoryEmpty(String category) {
    return 'لا يوجد مقدّمو خدمات في فئة $category بعد';
  }

  @override
  String svcReviewsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مراجعة',
      many: '$count مراجعة',
      few: '$count مراجعات',
      two: 'مراجعتان',
      one: 'مراجعة واحدة',
      zero: 'لا مراجعات',
    );
    return '$_temp0';
  }

  @override
  String svcOpenUntil(String time) {
    return 'مفتوح حتى $time';
  }

  @override
  String get svcTabAbout => 'نبذة';

  @override
  String svcFromPrice(String price) {
    return 'ابتداءً من $price';
  }

  @override
  String get svcOrderCta => 'اطلب';

  @override
  String get svcNoOffers => 'لا توجد عروض لدى مقدّم الخدمة هذا حاليًا';

  @override
  String get svcAboutHours => 'ساعات العمل';

  @override
  String get svcAboutAddress => 'العنوان';

  @override
  String get svcAboutGetIt => 'كيف تحصل على طلبك';

  @override
  String get svcPickupAtShop => 'الاستلام من المحل';

  @override
  String get svcYouDropDelivery => 'توصيل يودروب';

  @override
  String get svcClosedNoOrders => 'مغلق الآن — يمكنك الطلب عندما يفتح المحل';

  @override
  String get svcNeedsFileUnavailable =>
      'يحتاج هذا العرض إلى ملف، ولا يمكن إرسال الملفات مع الطلبات بعد';

  @override
  String svcPackOf(String count, String unit) {
    return 'حزمة من $count $unit';
  }

  @override
  String svcPerUnit(String unit) {
    return 'لكل $unit';
  }

  @override
  String get svcLoadMore => 'تحميل المزيد';

  @override
  String get svcCouldNotLoadOffer => 'تعذّر تحميل هذا العرض';

  @override
  String get svcCouldNotLoadReviews => 'تعذّر تحميل المراجعات';

  @override
  String get svcOrderServiceTitle => 'اطلب الخدمة';

  @override
  String svcProviderLine(String name) {
    return 'مقدّم الخدمة: $name';
  }

  @override
  String get svcQuantity => 'الكمية';

  @override
  String svcUnitsLine(String units, String unit) {
    return '$units $unit';
  }

  @override
  String svcPacksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count حزمة',
      many: '$count حزمة',
      few: '$count حزم',
      two: 'حزمتان',
      one: 'حزمة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get svcChooseOption => 'اختر واحدًا';

  @override
  String get svcOptionRequired => 'مطلوب';

  @override
  String get svcOptionOptional => 'اختياري';

  @override
  String get svcUploadDesign => 'ارفع ملف التصميم';

  @override
  String get svcUploadHint =>
      'اضغط لاختيار ملف PDF أو JPG أو PNG، حتى 10 ميغابايت';

  @override
  String get svcUploading => 'جارٍ الرفع…';

  @override
  String get svcUploaded => 'تم الرفع';

  @override
  String get svcRemoveFile => 'إزالة';

  @override
  String get svcUploadFailed => 'تعذّر رفع هذا الملف. حاول مجددًا.';

  @override
  String get svcAddAnotherFile => 'أضف ملفًا آخر';

  @override
  String get svcFileRequired => 'يحتاج مقدّم الخدمة إلى ملفك للبدء';

  @override
  String get svcSpecialInstructions => 'تعليمات خاصة';

  @override
  String get svcInstructionsHint => 'مثال: اترك إطارًا أبيض حول حواف البطاقة';

  @override
  String get svcHowYouGetIt => 'طريقة الحصول على الطلب';

  @override
  String svcDeliveryFeePlus(String amount) {
    return '+$amount';
  }

  @override
  String get svcPayCashPickup => 'نقدًا — ادفع عند الاستلام';

  @override
  String get svcPayCashDelivery => 'نقدًا — ادفع عند التوصيل';

  @override
  String get svcDeliveryFee => 'رسوم التوصيل';

  @override
  String get svcDiscount => 'الخصم';

  @override
  String svcPlaceOrderTotal(String amount) {
    return 'أكّد الطلب — $amount';
  }

  @override
  String get svcOfflineNoQueue =>
      'طلبات الخدمات تحتاج إلى اتصال — لا يمكن حفظها على هذا الهاتف لإرسالها لاحقًا.';

  @override
  String get svcChooseDeliveryAddress => 'اختر عنوان التوصيل';

  @override
  String get svcQuoteFailed => 'تعذّر الحصول على السعر. حاول مجددًا.';

  @override
  String svcPriceChangedBody(String total, String agreed) {
    return 'أصبح مجموع هذا الطلب $total بدلًا من $agreed الذي رأيته. هل تريد تأكيده بالمجموع الجديد؟';
  }

  @override
  String get svcDirectoryUnavailable =>
      'الخدمات غير متاحة مؤقتًا. حاول مجددًا بعد لحظات.';

  @override
  String svcNotServed(String shop) {
    return 'لا يوصل $shop إلى هذا العنوان';
  }

  @override
  String svcShopClosed(String shop) {
    return '$shop مغلق ولا يستقبل طلبات حاليًا';
  }

  @override
  String svcBelowMinimum(String shop, String amount) {
    return 'يوصل $shop الطلبات التي تبلغ $amount أو أكثر';
  }

  @override
  String get svcRefusedCategoryClosed => 'هذه الخدمة غير متاحة حاليًا';

  @override
  String get svcRefusedOfferNotOrderable => 'لا يمكن طلب هذا العرض حاليًا';

  @override
  String get svcRefusedFulfilment => 'لا يقدّم مقدّم الخدمة طريقة الحصول هذه';

  @override
  String get svcRefusedAttachmentsUnavailable =>
      'لا يمكن إرسال الملفات مع الطلبات بعد، لذا لا يمكن طلب هذا العرض';

  @override
  String get svcRefusedWrongType => 'ملفات PDF أو JPG أو PNG فقط';

  @override
  String get svcRefusedEmpty => 'هذا الملف فارغ';

  @override
  String get svcRefusedTooLarge => 'يجب ألا يتجاوز حجم الملف 10 ميغابايت';

  @override
  String get svcRefusedTooManyWaiting =>
      'لديك ملفات كثيرة بانتظار طلب. أزل أحدها أولًا.';

  @override
  String get svcRefusedNotUploaded => 'لم يكتمل رفع هذا الملف. ارفعه مجددًا.';

  @override
  String get svcRefusedExpired => 'انتهت صلاحية هذا الملف. ارفعه مجددًا.';

  @override
  String get svcRefusedAlreadyAttached =>
      'هذا الملف مرفق بطلب آخر. ارفعه مجددًا.';

  @override
  String get svcRefusedTooManyFiles => '3 ملفات كحدّ أقصى لكل طلب';

  @override
  String get svcRefusedDuplicate => 'هذا الملف مضاف بالفعل';

  @override
  String get svcRefusedNotAccepted => 'هذا العرض لا يقبل ملفات';

  @override
  String get svcRefusedUnknownFile =>
      'تعذّر العثور على هذا الملف. ارفعه مجددًا.';

  @override
  String get svcRefusedPacks => 'اختر بين 1 و99 حزمة';

  @override
  String get svcRefusedGeneric => 'لا يمكن تقديم هذا الطلب كما هو';

  @override
  String get svcTrackTitle => 'تتبّع طلب الخدمة';

  @override
  String svcOrderNumber(String ref) {
    return 'الطلب #$ref';
  }

  @override
  String get svcStatusWaiting => 'بانتظار مقدّم الخدمة';

  @override
  String get svcStatusInProgress => 'قيد التنفيذ';

  @override
  String get svcStatusReadyPickup => 'جاهز للاستلام';

  @override
  String get svcStatusReadyDelivery => 'جاهز للتوصيل';

  @override
  String get svcStatusOnTheWay => 'في الطريق';

  @override
  String get svcStatusCompleted => 'مكتمل';

  @override
  String get svcStatusCollected => 'تم الاستلام';

  @override
  String get svcStatusDeclined => 'مرفوض';

  @override
  String get svcStatusNotCollected => 'لم يُستلم';

  @override
  String get svcEstimatedCompletion => 'موعد الإنجاز المتوقع';

  @override
  String get svcReadyByCaption => 'جاهز بحلول';

  @override
  String svcEstimateAfterAccept(String range) {
    return '$range، ويُؤكَّد بعد قبول مقدّم الخدمة';
  }

  @override
  String svcTurnaroundRange(String min, String max) {
    return 'من $min إلى $max ساعة';
  }

  @override
  String svcTurnaroundUpTo(String max) {
    return 'حتى $max ساعة';
  }

  @override
  String svcTodayAt(String time) {
    return 'اليوم، $time';
  }

  @override
  String svcTomorrowAt(String time) {
    return 'غدًا، $time';
  }

  @override
  String svcDateAt(String date, String time) {
    return '$date، $time';
  }

  @override
  String get svcOrderStatusTitle => 'حالة الطلب';

  @override
  String get svcTimelinePlaced => 'تم تقديم الطلب';

  @override
  String get svcTimelineAccepted => 'قَبِل مقدّم الخدمة الطلب';

  @override
  String get svcTimelineInProduction => 'قيد الإنجاز';

  @override
  String get svcTimelineOutForDelivery => 'خرج للتوصيل';

  @override
  String svcDeclinedReason(String reason) {
    return 'رفض مقدّم الخدمة الطلب: $reason';
  }

  @override
  String get svcTimelineNotCollected => 'أُلغي — لم يُستلم في الوقت المحدد';

  @override
  String get svcProviderRole => 'مقدّم الخدمة';

  @override
  String get svcShowNumberAtPickup => 'أظهر رقم الطلب هذا عند الاستلام';

  @override
  String svcPickupFrom(String shop) {
    return 'الاستلام من $shop';
  }

  @override
  String svcDeliveringTo(String address) {
    return 'التوصيل إلى $address';
  }

  @override
  String get svcYourInstructions => 'تعليماتك';

  @override
  String get svcSummary => 'الملخص';

  @override
  String get svcServiceChip => 'خدمة';

  @override
  String get svcRefusedTooManyUploads =>
      'أرسلت عدة ملفات خلال الدقائق الأخيرة. انتظر بضع دقائق، ثم أضف هذا الملف من جديد.';

  @override
  String svcInstructionsLength(int used, int max) {
    return '$used من $max';
  }

  @override
  String get svcOrderNotAccepted =>
      'تعذّر إرسال هذا الطلب كما هو. راجع ما كتبته فيه، ثم حاول مجددًا.';

  @override
  String get svcOrderChangedRequote =>
      'تغيّر طلبك أثناء إرساله، لذا لم يُرسَل شيء. نتحقق الآن من مجموعه من جديد.';

  @override
  String get svcUnconfirmedLeaveTitle => 'ربما وصل طلبك';

  @override
  String get svcUnconfirmedLeaveBody =>
      'لم يصلنا ردّ بعد أن ضغطت «اطلب». راجع طلباتك قبل أن تطلبه مجددًا، كي لا تطلبه مرتين.';

  @override
  String get svcCheckOrders => 'راجع الطلبات';

  @override
  String get svcLeaveAnyway => 'غادر على أي حال';

  @override
  String get svcStayHere => 'ابقَ هنا';

  @override
  String get svcYourFiles => 'ملفاتك';

  @override
  String svcYourFileNumber(int n) {
    return 'الملف $n';
  }

  @override
  String get svcYourFilesFailed => 'تعذّر تحميل ملفاتك';

  @override
  String get svcFileGone => 'هذا الملف لم يعد متاحًا.';

  @override
  String svcRateProvider(String shop) {
    return 'قيّم $shop';
  }

  @override
  String get svcRateProviderPrompt => 'كيف كان العمل؟';

  @override
  String svcRatedProvider(String shop) {
    return 'لقد قيّمت $shop';
  }

  @override
  String get svcReviewNotYet =>
      'لم يُسجَّل هذا الطلب مكتملًا بعد، لذا لا يمكن تقييمه الآن. حاول مجددًا بعد دقيقة.';

  @override
  String get svcBoOffersTitle => 'عروض الخدمات';

  @override
  String get svcBoOffersSubtitle =>
      'عروض كل متاجر الخدمات بكل حالاتها — احجب عرضًا أو أعِده مع ذكر السبب';

  @override
  String get svcBoShopsTitle => 'المتاجر';

  @override
  String get svcBoShopsSubtitle =>
      'المتاجر المُدرجة، وأيّها يحمل شارة «محل موثوق»';

  @override
  String get svcBoFilterAll => 'الكل';

  @override
  String get svcBoOfferDraft => 'مسودة';

  @override
  String get svcBoOfferActive => 'نشط';

  @override
  String get svcBoOfferPaused => 'متوقف مؤقتًا';

  @override
  String get svcBoOfferArchived => 'مؤرشف';

  @override
  String get svcBoOfferTakenDown => 'محجوب';

  @override
  String get svcBoAllCategories => 'كل الفئات';

  @override
  String get svcBoAllShops => 'كل المتاجر';

  @override
  String get svcBoShopFilterTooltip => 'المتاجر التي ظهرت في النتائج حتى الآن';

  @override
  String get svcBoOffersSearchHint => 'ابحث باسم العرض أو المتجر';

  @override
  String get svcBoColOffer => 'العرض';

  @override
  String get svcBoColShop => 'المتجر';

  @override
  String get svcBoColCategory => 'الفئة';

  @override
  String get svcBoColPrice => 'السعر';

  @override
  String get svcBoColStatus => 'الحالة';

  @override
  String get svcBoOffersEmpty => 'لا توجد عروض خدمات تطابق هذه التصفية.';

  @override
  String get svcBoOffersLoadFailed => 'تعذّر تحميل عروض الخدمات.';

  @override
  String get svcBoOffersRefused =>
      'لا يُسمح لهذا الحساب بقراءة عروض الخدمات — هذا متاح لموظفي الإدارة فقط.';

  @override
  String svcBoPageOf(int page, int pages) {
    return 'الصفحة $page من $pages';
  }

  @override
  String svcBoOffersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عرض',
      many: '$count عرضًا',
      few: '$count عروض',
      two: 'عرضان',
      one: 'عرض واحد',
      zero: 'لا عروض',
    );
    return '$_temp0';
  }

  @override
  String svcBoPriceFrom(String price) {
    return 'ابتداءً من $price';
  }

  @override
  String svcBoPricePer(String price, String unit) {
    return '$price لكل $unit';
  }

  @override
  String svcBoPricePerPack(String price, int count, String unit) {
    return '$price لكل $count $unit';
  }

  @override
  String get svcBoSectionOffer => 'العرض';

  @override
  String get svcBoSectionShop => 'متجر مقدّم الخدمة';

  @override
  String get svcBoSectionTerms => 'الشروط';

  @override
  String get svcBoSectionPhotos => 'الصور';

  @override
  String get svcBoSectionHold => 'محجوب عن البيع';

  @override
  String get svcBoSectionModerationHistory => 'سجل الإدارة';

  @override
  String get svcBoFactDescription => 'الوصف';

  @override
  String get svcBoFactName => 'الاسم';

  @override
  String get svcBoFactListing => 'الإدراج';

  @override
  String get svcBoShopListed => 'مُدرج';

  @override
  String get svcBoShopDraft => 'غير مُدرج بعد';

  @override
  String get svcBoShopSuspended => 'معلّق';

  @override
  String get svcBoTermPricing => 'التسعير';

  @override
  String get svcBoPricingFixed => 'سعر ثابت';

  @override
  String get svcBoPricingPerUnit => 'لكل وحدة';

  @override
  String get svcBoPricingFrom => 'سعر ابتدائي';

  @override
  String get svcBoTermUnknown => 'غير معروف لهذا الإصدار';

  @override
  String get svcBoTermPack => 'العبوة الواحدة';

  @override
  String svcBoPackOf(int count, String unit) {
    return '$count $unit';
  }

  @override
  String svcBoPackUnits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count وحدة',
      many: '$count وحدة',
      few: '$count وحدات',
      two: 'وحدتان',
      one: 'وحدة واحدة',
      zero: 'لا وحدات',
    );
    return '$_temp0';
  }

  @override
  String get svcBoTermTurnaround => 'مدة التنفيذ';

  @override
  String svcBoTurnaroundRange(int min, int max) {
    return '$min–$max ساعة';
  }

  @override
  String svcBoTurnaroundUpTo(int max) {
    return 'حتى $max ساعة';
  }

  @override
  String get svcBoTermFulfilment => 'طريقة التسليم';

  @override
  String get svcBoFulfilPickup => 'استلام من المتجر';

  @override
  String get svcBoFulfilDelivery => 'توصيل YouDrop';

  @override
  String get svcBoFulfilBoth => 'استلام أو توصيل';

  @override
  String get svcBoTermFiles => 'ملفات الزبون';

  @override
  String get svcBoFilesPolicyNone => 'بدون ملفات';

  @override
  String get svcBoFilesPolicyOptional => 'اختيارية';

  @override
  String get svcBoFilesPolicyRequired => 'إلزامية';

  @override
  String get svcBoTermPrompt => 'سؤال للزبون';

  @override
  String get svcBoNoPhotos => 'لا توجد صور';

  @override
  String get svcBoPhotoUnavailable => 'الصورة غير متاحة';

  @override
  String get svcBoOpenPhoto => 'فتح الصورة بالحجم الكامل';

  @override
  String get svcBoPhoto => 'صورة';

  @override
  String svcBoPhotoPosition(int index, int count) {
    return '$index من $count';
  }

  @override
  String get svcBoHoldReason => 'السبب المذكور';

  @override
  String get svcBoHoldSince => 'منذ';

  @override
  String get svcBoTakeDown => 'حجب العرض';

  @override
  String get svcBoRestore => 'إعادة العرض';

  @override
  String svcBoTakeDownTitle(String offer) {
    return 'حجب $offer؟';
  }

  @override
  String get svcBoTakeDownBody =>
      'يُسحب من البيع لجميع الزبائن فورًا. يقرأ مقدّم الخدمة سببك، ولا يمكنه إعادته إلى البيع حتى تعيده الإدارة.';

  @override
  String svcBoRestoreTitle(String offer) {
    return 'إعادة $offer؟';
  }

  @override
  String get svcBoRestoreBody =>
      'يُرفع الحجب. العرض الذي كان معروضًا للبيع يعود متوقفًا مؤقتًا ليستأنفه مقدّم الخدمة.';

  @override
  String get svcBoReasonLabel => 'السبب — إلزامي ويُحفظ في السجل';

  @override
  String get svcBoReasonRequired => 'اذكر السبب: السبب إلزامي.';

  @override
  String svcBoTakenDownDone(String offer) {
    return 'حُجب $offer. يمكن لمقدّم الخدمة قراءة سببك.';
  }

  @override
  String svcBoRestoredDone(String offer) {
    return 'أُعيد $offer. إن كان معروضًا للبيع فهو ينتظر متوقفًا مؤقتًا حتى يستأنفه مقدّم الخدمة.';
  }

  @override
  String get svcBoTakeDownRefused =>
      'لم يُحجب: يفيد الخادم بأن هذا العرض محجوب أصلًا أو ليس عرض خدمة. لم يتغيّر شيء وأُعيد تحميل القائمة.';

  @override
  String get svcBoRestoreRefused =>
      'لم يُعَد: يفيد الخادم بأن هذا العرض لم يعد محجوبًا. لم يتغيّر شيء وأُعيد تحميل القائمة.';

  @override
  String get svcBoOfferChanged =>
      'تغيّر هذا العرض أثناء إجرائك، لذلك لم يُسجَّل شيء. أُعيد تحميله؛ حاول مجددًا.';

  @override
  String get svcBoOfferGone => 'هذا العرض لم يعد موجودًا.';

  @override
  String get svcBoModerateRefused => 'لا يُسمح لهذا الحساب بإدارة العروض.';

  @override
  String svcBoReasonRejected(int max) {
    return 'لم يقبل الخادم هذا السبب. اكتب سببًا لا يتجاوز $max حرفًا.';
  }

  @override
  String get svcBoActionFailed => 'لم يتم الإجراء ولم يتغيّر شيء. حاول مجددًا.';

  @override
  String get svcBoHistoryNever => 'لم تتخذ الإدارة أي إجراء بشأن هذا العرض.';

  @override
  String get svcBoHistoryLoadFailed => 'تعذّر تحميل السجل.';

  @override
  String get svcBoActTakeDown => 'حُجب';

  @override
  String get svcBoActRestore => 'أُعيد';

  @override
  String get svcBoActUnknown => 'إجراء لا يعرفه هذا الإصدار';

  @override
  String svcBoActBy(String actor) {
    return 'بواسطة $actor';
  }

  @override
  String get svcBoKindAll => 'كل الأنواع';

  @override
  String get svcBoKindService => 'طلبات الخدمات';

  @override
  String get svcBoFulfilmentAll => 'الاستلام والتوصيل';

  @override
  String get svcBoFulfilmentPickup => 'استلام';

  @override
  String get svcBoFulfilmentDelivery => 'توصيل';

  @override
  String get svcBoServiceTag => 'خدمة';

  @override
  String get svcBoStatusPlaced => 'تم الطلب';

  @override
  String get svcBoStatusAccepted => 'مقبول';

  @override
  String get svcBoStatusInProduction => 'قيد التنفيذ';

  @override
  String get svcBoStatusReadyPickup => 'جاهز للاستلام';

  @override
  String get svcBoStatusReadyDelivery => 'جاهز للتوصيل';

  @override
  String get svcBoStatusOnTheWay => 'في الطريق';

  @override
  String get svcBoStatusCollected => 'تم الاستلام';

  @override
  String get svcBoStatusDelivered => 'تم التوصيل';

  @override
  String get svcBoStatusDeclined => 'رفضه مقدّم الخدمة';

  @override
  String get svcBoStatusNotCollected => 'أُلغي: لم يُستلم';

  @override
  String get svcBoStatusCancelled => 'أُلغي';

  @override
  String get svcBoDetailKind => 'النوع';

  @override
  String svcBoKindServiceIn(String category) {
    return 'خدمة · $category';
  }

  @override
  String get svcBoDetailService => 'الخدمة';

  @override
  String svcBoPacksOfUnits(int packs, int size, String unit) {
    return '$packs × $size $unit';
  }

  @override
  String svcBoPacksOf(int packs, int size) {
    return '$packs × $size';
  }

  @override
  String get svcBoDetailOptions => 'الخيارات';

  @override
  String get svcBoDetailInstructions => 'التعليمات';

  @override
  String get svcBoNoInstructions => 'لم تُكتب تعليمات';

  @override
  String get svcBoDetailReadyBy => 'الجاهزية المتوقعة';

  @override
  String get svcBoHistoryTitle => 'سجل الحالة';

  @override
  String get svcBoHistoryNone => 'لا توجد خطوات مسجّلة بعد.';

  @override
  String get svcBoHistoryFailed => 'تعذّر تحميل سجل الحالة.';

  @override
  String get svcBoFilesTitle => 'ملفات الزبون';

  @override
  String get svcBoFilesAuditNotice =>
      'تُسجَّل قراءات الإدارة لملفات الزبون: عرضها يسجّل حسابك مقابل كل ملف.';

  @override
  String get svcBoFilesShow => 'عرض الملفات';

  @override
  String get svcBoFilesNotTaken => 'هذا العرض لا يقبل ملفات.';

  @override
  String get svcBoFilesEmpty =>
      'لا توجد ملفات على هذا الطلب. تُحذف الملفات بعد 90 يومًا من اكتمال الطلب.';

  @override
  String get svcBoFileOpen => 'فتح';

  @override
  String get svcBoFileOpened =>
      'فُتح في علامة تبويب جديدة. وصولك إلى هذا الملف مسجَّل.';

  @override
  String get svcBoFilePdf => 'ملف PDF';

  @override
  String get svcBoFileImage => 'صورة';

  @override
  String get svcBoFileOther => 'ملف';

  @override
  String svcBoSizeMb(String size) {
    return '$size ميغابايت';
  }

  @override
  String svcBoSizeKb(String size) {
    return '$size كيلوبايت';
  }

  @override
  String get svcBoFilesRefused => 'رفض الخادم عرض ملفات هذا الطلب.';

  @override
  String get svcBoFilesUnavailable =>
      'تعذّر الوصول إلى الملفات الآن. حاول بعد قليل.';

  @override
  String get svcBoFilesFailed => 'تعذّر تحميل الملفات.';

  @override
  String get svcBoLedgerRefused => 'لا يُسمح لهذا الحساب بقراءة سجل الطلبات.';

  @override
  String get svcBoShopsGoods => 'متاجر السلع';

  @override
  String get svcBoShopsServices => 'متاجر الخدمات';

  @override
  String get svcBoShopsSearchHint => 'ابحث باسم المتجر';

  @override
  String get svcBoShopsListedOnly =>
      'تظهر هنا فقط المتاجر المُدرجة في الواجهة.';

  @override
  String get svcBoShopsEmpty => 'لا توجد متاجر مُدرجة مطابقة.';

  @override
  String get svcBoShopsLoadFailed => 'تعذّر تحميل المتاجر.';

  @override
  String svcBoVerifyGrantTitle(String shop) {
    return 'منح $shop شارة «محل موثوق»؟';
  }

  @override
  String get svcBoVerifyGrantBody =>
      'يرى الزبائن الشارة على هذا المتجر أينما ظهر. إنها شهادة من YouDrop لجيران المتجر، فامنحها فقط لمتجر تم التحقق منه.';

  @override
  String svcBoVerifyRevokeTitle(String shop) {
    return 'إزالة شارة «محل موثوق» عن $shop؟';
  }

  @override
  String get svcBoVerifyRevokeBody =>
      'تختفي الشارة عن هذا المتجر لدى جميع الزبائن.';

  @override
  String get svcBoVerifyGrant => 'منح الشارة';

  @override
  String get svcBoVerifyRevoke => 'إزالة الشارة';

  @override
  String svcBoVerifyGranted(String shop) {
    return 'أصبح $shop «محلًا موثوقًا».';
  }

  @override
  String svcBoVerifyRevoked(String shop) {
    return 'لم يعد $shop «محلًا موثوقًا».';
  }

  @override
  String get svcBoVerifyRefused => 'تغيير هذه الشارة متاح للإدارة فقط.';

  @override
  String get svcBoVerifyGone => 'هذا المتجر لم يعد موجودًا.';

  @override
  String get svcBoVerifyFailed => 'لم تتغيّر الشارة. حاول مجددًا.';

  @override
  String svcBoVerifiedToggle(String shop) {
    return 'شارة «محل موثوق» لـ $shop';
  }

  @override
  String svcBoReasonLength(int used, int max) {
    return '$used من $max';
  }

  @override
  String get svcBoOfferNotListed =>
      'لم يُسجَّل شيء، وهذا العرض لم يعد ضمن عروض الخدمات، لذلك لم يبقَ ما يُتخذ بشأنه إجراء.';

  @override
  String get svcBoOfferUnreadable =>
      'لم يُسجَّل شيء، لكن تعذّرت إعادة قراءة هذا العرض، لذلك قد لا يكون المعروض محدَّثًا. أغلقه ثم افتحه مجددًا من القائمة.';

  @override
  String get svcNavOffers => 'خدماتي';

  @override
  String get svcDashboardActiveOffers => 'خدمات متاحة';

  @override
  String get svcDashboardThisWeek => 'هذا الأسبوع';

  @override
  String get svcDashboardThisWeekCaption => 'الطلبات في آخر 7 أيام';

  @override
  String get svcDashboardRating => 'التقييم';

  @override
  String get svcQuickActions => 'إجراءات سريعة';

  @override
  String get svcAddOffer => 'أضف خدمة';

  @override
  String get svcViewOrders => 'عرض الطلبات';

  @override
  String get svcCurrentOffers => 'خدماتك الحالية';

  @override
  String get svcSeeAllOffers => 'عرض الكل';

  @override
  String get svcOfferActive => 'متاحة';

  @override
  String get svcOfferPaused => 'متوقفة';

  @override
  String get svcOfferDraft => 'مسودة';

  @override
  String get svcPauseOffer => 'إيقاف مؤقت';

  @override
  String get svcResumeOffer => 'استئناف';

  @override
  String get svcOfferPausedDone =>
      'أوقفت الخدمة مؤقتًا. لن يتمكن الزبائن من طلبها حتى تستأنفها.';

  @override
  String get svcOfferResumedDone => 'الخدمة متاحة من جديد.';

  @override
  String get svcNoOffersYet => 'لا خدمات بعد';

  @override
  String get svcNoOffersYetBody => 'أضف خدمتك الأولى ليتمكن الزبائن من طلبها.';

  @override
  String get svcDashboardLoadFailed => 'تعذّر تحميل لوحة التحكم';

  @override
  String get svcOffersLoadFailed => 'تعذّر تحميل خدماتك';

  @override
  String get svcNoShopYet => 'متجر خدماتك لم يُفتح بعد';

  @override
  String get svcNoShopYetBody => 'سيُفتح فور الموافقة على طلبك.';

  @override
  String get svcPublishAfterApproval =>
      'يمكنك نشر خدماتك بعد الموافقة على طلبك.';

  @override
  String get svcOffersTitle => 'خدماتك';

  @override
  String get svcOffersSubtitle => 'ما يمكن للزبائن طلبه منك';

  @override
  String svcUnitPack(String count, String unit) {
    return '$count $unit';
  }

  @override
  String svcUnitPer(String unit) {
    return 'لكل $unit';
  }

  @override
  String svcPriceUsd(String amount) {
    return '$amount \$';
  }

  @override
  String svcPriceLbp(String amount) {
    return '$amount ل.ل.';
  }

  @override
  String svcLbpPreview(String amount) {
    return '≈ $amount بسعر اليوم';
  }

  @override
  String get svcNewOffer => 'خدمة جديدة';

  @override
  String get svcEditOffer => 'تعديل الخدمة';

  @override
  String get svcOfferTitle => 'اسم الخدمة';

  @override
  String get svcOfferTitleRequired => 'أدخل اسم الخدمة';

  @override
  String svcTooLong(String max) {
    return '$max حرفًا كحد أقصى';
  }

  @override
  String get svcDescription => 'الوصف';

  @override
  String get svcCategory => 'الفئة';

  @override
  String get svcCategoryOfShop => 'تأخذ الخدمات فئة متجرك';

  @override
  String get svcPriceLabel => 'السعر (بالدولار الأمريكي)';

  @override
  String get svcPriceInvalid =>
      'أدخل سعرًا أكبر من صفر بخانتين عشريتين على الأكثر';

  @override
  String get svcPricingType => 'طريقة التسعير';

  @override
  String get svcPricingFixed => 'سعر ثابت';

  @override
  String get svcPricingPerUnit => 'سعر للوحدة';

  @override
  String get svcPricingFrom => 'سعر ابتدائي (تُضاف إليه الخيارات)';

  @override
  String get svcUnitLabel => 'الوحدة (مثل: بطاقة، متر مربع)';

  @override
  String get svcPackSize => 'عدد الوحدات في كل خطوة';

  @override
  String get svcUnitRequired => 'حدّد الوحدة، مثل بطاقة أو متر مربع';

  @override
  String svcPackSizeRange(String min, String max) {
    return 'بين $min و$max';
  }

  @override
  String get svcPerUnitIsOne => 'سعر الوحدة هو سعر وحدة واحدة';

  @override
  String svcPackPreview(String pack) {
    return 'يطلب الزبائن بخطوات من $pack';
  }

  @override
  String get svcPhotos => 'الصور';

  @override
  String get svcPhotoRequired => 'أضف صورة واحدة على الأقل لتنشر';

  @override
  String get svcAddPhoto => 'أضف صورة';

  @override
  String get svcTurnaround => 'مدة التنفيذ';

  @override
  String get svcTurnaroundSameDay => 'في اليوم نفسه';

  @override
  String get svcTurnaround1to2 => 'من يوم إلى يومين';

  @override
  String get svcTurnaround3to5 => 'من 3 إلى 5 أيام';

  @override
  String get svcTurnaroundWeek => 'نحو أسبوع';

  @override
  String svcTurnaroundHours(String min, String max) {
    return '$min–$max ساعة';
  }

  @override
  String get svcTurnaroundRequired => 'اختر مدة التنفيذ';

  @override
  String get svcFulfilment => 'كيف يحصل الزبون عليها';

  @override
  String get svcFulfilmentPickup => 'الاستلام من متجرك';

  @override
  String get svcFulfilmentDelivery => 'توصيل يو دروب';

  @override
  String get svcFulfilmentBoth => 'الاثنان معًا';

  @override
  String get svcFulfilmentRequired => 'اختر كيف يحصل الزبون عليها';

  @override
  String get svcDeliveryNeedsAreas =>
      'حدّد مناطق التوصيل أو ثبّت موقع متجرك قبل عرض توصيل يو دروب';

  @override
  String get svcCustomerFile => 'ملف من الزبون';

  @override
  String get svcCustomerFileNone => 'غير مطلوب';

  @override
  String get svcCustomerFileOptional => 'اختياري';

  @override
  String get svcCustomerFileRequired => 'مطلوب';

  @override
  String get svcInstructionsPrompt => 'ماذا يجب أن يخبرك الزبون؟';

  @override
  String get svcInstructionsPromptHint =>
      'مثال: الأسماء والمسميات المطلوب طباعتها';

  @override
  String get svcOptions => 'الخيارات';

  @override
  String get svcOptionsAfterSave =>
      'احفظ الخدمة أولًا، ثم أضف خيارات مثل نوع الورق';

  @override
  String get svcEditOptions => 'تعديل الخيارات';

  @override
  String get svcNoOptions => 'لا خيارات';

  @override
  String get svcPublishOffer => 'انشر الخدمة';

  @override
  String get svcSaveDraft => 'احفظ كمسودة';

  @override
  String get svcSaveChanges => 'احفظ التغييرات';

  @override
  String get svcOfferPublished => 'نُشرت الخدمة';

  @override
  String get svcDraftSaved => 'حُفظت المسودة';

  @override
  String get svcOfferSaveFailed => 'تعذّر حفظ الخدمة';

  @override
  String get svcOfferRefused =>
      'لم تُقبل الخدمة بصيغتها الحالية. راجع تفاصيلها وحاول مجددًا.';

  @override
  String get svcArchiveOffer => 'أرشفة الخدمة';

  @override
  String get svcArchiveConfirm =>
      'أرشفة هذه الخدمة؟ لن يراها الزبائن بعد الآن.';

  @override
  String get svcOfferArchived => 'أُرشفت الخدمة';

  @override
  String get svcOfferNotEditable =>
      'تستخدم هذه الخدمة إعدادات لا يستطيع هذا الإصدار من التطبيق تعديلها. حدّث التطبيق لتعديلها.';

  @override
  String get svcMoreActions => 'إجراءات أخرى';

  @override
  String get svcIncomingOrders => 'الطلبات الواردة';

  @override
  String get svcTabNew => 'جديدة';

  @override
  String get svcTabInProgress => 'قيد التنفيذ';

  @override
  String get svcTabCompleted => 'مكتملة';

  @override
  String get svcChipNew => 'جديد';

  @override
  String get svcChipAccepted => 'مقبول';

  @override
  String get svcChipInProduction => 'قيد الإنتاج';

  @override
  String get svcChipReady => 'جاهز';

  @override
  String get svcChipOnTheWay => 'في الطريق';

  @override
  String get svcChipCollected => 'استُلم';

  @override
  String get svcChipDelivered => 'وُصِّل';

  @override
  String get svcChipDeclined => 'مرفوض';

  @override
  String get svcChipNotCollected => 'لم يُستلم';

  @override
  String get svcChipCancelled => 'ملغى';

  @override
  String get svcChipPickup => 'استلام';

  @override
  String get svcChipDelivery => 'توصيل';

  @override
  String get svcAcceptOrder => 'اقبل الطلب';

  @override
  String get svcDecline => 'ارفض';

  @override
  String get svcDeclineTitle => 'لماذا ترفض الطلب؟';

  @override
  String get svcDeclineBody => 'سيرى الزبون السبب الذي تختاره.';

  @override
  String get svcDeclineConfirm => 'ارفض الطلب';

  @override
  String get svcWaitingForPickup => 'بانتظار أن يستلمه الزبون';

  @override
  String get svcWaitingForRider => 'بانتظار السائق';

  @override
  String svcReadyBy(String time) {
    return 'جاهز بحلول $time';
  }

  @override
  String svcAcceptedReadyBy(String time) {
    return 'قُبل الطلب. موعد جاهزيته $time.';
  }

  @override
  String get svcAccepted => 'قُبل الطلب';

  @override
  String get svcMarkedReady => 'حُدِّد كجاهز';

  @override
  String get svcNoNewOrders => 'لا طلبات جديدة';

  @override
  String get svcNoOrdersInProgress => 'لا شيء قيد التنفيذ';

  @override
  String get svcNoCompletedOrders => 'لا طلبات مكتملة بعد';

  @override
  String get svcOrdersEmptyBody => 'تظهر الطلبات هنا عندما يطلبها الزبائن.';

  @override
  String get svcCancelNotCollected => 'ألغِ لعدم الاستلام';

  @override
  String svcCancelNotCollectedIn(String time) {
    return 'يمكنك إلغاؤه لعدم الاستلام بعد $time';
  }

  @override
  String get svcCancelNotCollectedTitle => 'إلغاء هذا الطلب غير المستلم؟';

  @override
  String get svcCancelNotCollectedBody =>
      'سيُبلَّغ الزبون أن الطلب أُلغي لأنه لم يُستلم.';

  @override
  String get svcCancelNotCollectedNote => 'ملاحظة للزبون (اختيارية)';

  @override
  String get svcKeepOrder => 'أبقِ الطلب';

  @override
  String svcDurationDaysHours(String days, String hours) {
    return '$days يوم و$hours ساعة';
  }

  @override
  String svcDurationHoursMinutes(String hours, String minutes) {
    return '$hours ساعة و$minutes دقيقة';
  }

  @override
  String svcDurationMinutes(String minutes) {
    return '$minutes دقيقة';
  }

  @override
  String get svcRefusedNotDeclinable =>
      'قُبل هذا الطلب في هذه الأثناء، فلا يمكن رفضه. جارٍ التحديث.';

  @override
  String get svcRefusedNotCollectable =>
      'لم يعد هذا الطلب بانتظار الاستلام لديك. جارٍ التحديث.';

  @override
  String get svcRefusedTooSoon =>
      'الوقت مبكر: ما زال أمام الزبون وقت للاستلام. جارٍ التحديث.';

  @override
  String get svcRefusedOther => 'تعذّر تعديل الطلب. جارٍ التحديث.';

  @override
  String get svcOrderDeclined => 'رُفض الطلب';

  @override
  String get svcOrderCollected => 'سُجِّل الاستلام';

  @override
  String get svcOrderCancelledNotCollected => 'أُلغي لعدم الاستلام';

  @override
  String svcOrderTitle(String id) {
    return 'الطلب $id';
  }

  @override
  String get svcChatWithCustomer => 'راسل الزبون';

  @override
  String get svcTheJob => 'العمل المطلوب';

  @override
  String get svcInstructions => 'تعليمات خاصة';

  @override
  String get svcNoInstructions => 'لم تُذكر تعليمات';

  @override
  String get svcCustomerFiles => 'ملفات الزبون';

  @override
  String get svcNoFiles => 'لم تُرسَل ملفات';

  @override
  String get svcFilesLoadFailed => 'تعذّر تحميل الملفات';

  @override
  String get svcOpenFile => 'افتح';

  @override
  String get svcFileCouldNotOpen => 'تعذّر فتح هذا الملف';

  @override
  String get svcFileDocument => 'مستند';

  @override
  String get svcFileImage => 'صورة';

  @override
  String svcFileSizeKb(String size) {
    return '$size ك.ب';
  }

  @override
  String svcFileSizeMb(String size) {
    return '$size م.ب';
  }

  @override
  String get svcFulfilmentPickupDetail => 'يستلمه الزبون من متجرك';

  @override
  String svcFulfilmentDeliveryDetail(String address) {
    return 'يوصله السائق إلى $address';
  }

  @override
  String get svcEstimatedReady => 'الجاهزية المتوقعة';

  @override
  String svcTurnaroundAfterAccept(String range) {
    return 'مدة التنفيذ بعد القبول: $range';
  }

  @override
  String get svcRiderOnTheWay => 'السائق في طريقه لاستلامه';

  @override
  String get svcFileLinkRefreshFailed =>
      'تعذّر الحصول على رابط جديد لهذا الملف. حاول مجددًا.';

  @override
  String get svcOfferTakenDown => 'سحبتها يو دروب';

  @override
  String svcOfferTakenDownReason(String reason) {
    return 'سبب يو دروب: $reason';
  }

  @override
  String get svcOfferTakenDownBody =>
      'لا يستطيع الزبائن طلبها، ولا يمكن نشرها أو إيقافها مؤقتًا أو استئنافها حتى تعيدها يو دروب. ما زال بإمكانك تعديلها.';

  @override
  String get svcOfferChangedElsewhere =>
      'عُدّلت هذه الخدمة للتو من مكان آخر، فأعدنا قراءتها. راجعها وحاول مجددًا.';

  @override
  String get svcShopReadFailed => 'تعذّر تحميل متجرك';

  @override
  String get svcServiceOrdersRow => 'طلبات الخدمات';

  @override
  String get svcServiceOffersRow => 'خدماتك';

  @override
  String svcChatOrderLabel(String ref) {
    return 'الطلب $ref';
  }

  @override
  String svcChatClosedOn(String date) {
    return 'أُغلقت المحادثة بشأن هذا الطلب في $date';
  }

  @override
  String get svcChatClosed => 'أُغلقت المحادثة بشأن هذا الطلب';

  @override
  String get svcChatUnavailable => 'المحادثة غير متاحة حاليًا.';

  @override
  String get svcChatOrderNotFound => 'تعذّر فتح محادثة هذا الطلب. نعيد تحميله.';

  @override
  String get isrchSearchHint => 'ابحث عن متاجر وأطباق وأصناف';

  @override
  String get isrchNearTitle => 'أصناف في متاجر قريبة منك';

  @override
  String get isrchAnywhereTitle => 'أصناف في المتاجر';

  @override
  String get isrchSeeAll => 'عرض كل الأصناف';

  @override
  String get isrchFieldHint => 'ابحث عن صنف في المتاجر';

  @override
  String isrchEmptyNear(String query) {
    return 'لا يتوفر «$query» الآن في أي متجر مفتوح قريب منك';
  }

  @override
  String isrchEmptyAnywhere(String query) {
    return 'لا يتوفر «$query» الآن في أي متجر مفتوح';
  }

  @override
  String isrchEmptyTruncated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'لم نفحص إلا أفضل $count نتيجة.',
      many: 'لم نفحص إلا أفضل $count نتيجةً.',
      few: 'لم نفحص إلا أفضل $count نتائج.',
      two: 'لم نفحص إلا أفضل نتيجتين.',
      one: 'لم نفحص إلا أفضل نتيجة.',
      zero: 'لم نفحص أي نتيجة.',
    );
    return '$_temp0';
  }

  @override
  String get isrchNotByDistance =>
      'عنوانك غير محدد على الخريطة، لذا لم تُرتَّب المتاجر حسب المسافة.';

  @override
  String isrchMoreInStore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صنف آخر في هذا المتجر',
      many: '$count صنفًا آخر في هذا المتجر',
      few: '$count أصناف أخرى في هذا المتجر',
      two: 'صنفان آخران في هذا المتجر',
      one: 'صنف آخر في هذا المتجر',
      zero: 'لا مزيد في هذا المتجر',
    );
    return '$_temp0';
  }

  @override
  String get isrchCouldNotSearch => 'تعذّر البحث عن الأصناف الآن.';

  @override
  String get isrchTypeMore => 'اكتب حرفين على الأقل للبحث عن الأصناف.';

  @override
  String get isrchSearching => 'جارٍ البحث عن الأصناف';

  @override
  String get isrchUseFewerWords =>
      'استخدم خمس كلمات على الأكثر للبحث عن الأصناف.';
}
