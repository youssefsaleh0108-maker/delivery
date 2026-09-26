package com.delivery.product.shoppage;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalTime;
import java.util.List;
import java.util.Locale;

import com.delivery.product.domain.Store;

/**
 * The public page in Arabic and English: the words, the direction, and the digits.
 *
 * <p>No properties bundle and no {@code MessageSource}. There are two languages and one page, the
 * strings are read beside the markup that uses them, and a missing key here is a compile error
 * rather than a {@code ???openNow???} on the one page a stranger reads.
 *
 * <p>Numbers are the part that is easy to get wrong. The Arabic app writes its numerals in
 * Arabic-Indic digits — the ARB strings carry them literally ({@code "شارع الاختبار ١٢"}) and
 * everything interpolated goes through {@code Intl} in {@code ar}, which renders U+0660..U+0669
 * with U+066C between thousands and U+066B before a fraction. A page that set an Arabic shop's
 * hours in Latin digits would be the only Arabic surface on the platform that did.
 */
enum ShopPageText {

    EN("en", "ltr"),
    AR("ar", "rtl");

    private final String tag;
    private final String dir;

    ShopPageText(String tag, String dir) {
        this.tag = tag;
        this.dir = dir;
    }

    String tag() {
        return tag;
    }

    String dir() {
        return dir;
    }

    boolean arabic() {
        return this == AR;
    }

    ShopPageText other() {
        return this == AR ? EN : AR;
    }

    /**
     * Which language to draw, from the query string first and the browser second.
     *
     * <p>{@code ?lang=} wins over {@code Accept-Language} because it is the one a person chose:
     * the link at the bottom of the page is how a reader whose phone is set to English reads an
     * Arabic shop's page in Arabic, and a header that overrode it would make that link do nothing.
     *
     * <p>The header is matched on the language subtag alone, anywhere in the list, and Arabic wins
     * only if it is ranked at least as highly as English. Full RFC 4647 negotiation for a choice
     * between two languages would be a lot of machinery to answer the same question.
     */
    static ShopPageText choose(String langParam, String acceptLanguage) {
        if (langParam != null) {
            String wanted = langParam.trim().toLowerCase(Locale.ROOT);
            if (wanted.startsWith("ar")) {
                return AR;
            }
            if (wanted.startsWith("en")) {
                return EN;
            }
        }
        return prefersArabic(acceptLanguage) ? AR : EN;
    }

    private static boolean prefersArabic(String acceptLanguage) {
        if (acceptLanguage == null || acceptLanguage.isBlank()) {
            return false;
        }
        double arabic = -1;
        double english = -1;
        for (String part : acceptLanguage.split(",")) {
            String[] pieces = part.trim().split(";");
            String tag = pieces[0].trim().toLowerCase(Locale.ROOT);
            double quality = 1.0;
            for (int i = 1; i < pieces.length; i++) {
                String parameter = pieces[i].trim();
                if (parameter.startsWith("q=")) {
                    try {
                        quality = Double.parseDouble(parameter.substring(2));
                    } catch (NumberFormatException malformed) {
                        quality = 0;
                    }
                }
            }
            if (tag.equals("ar") || tag.startsWith("ar-")) {
                arabic = Math.max(arabic, quality);
            } else if (tag.equals("en") || tag.startsWith("en-")) {
                english = Math.max(english, quality);
            }
        }
        return arabic > 0 && arabic >= english;
    }

    // ---------------------------------------------------------------- numbers

    /**
     * Digits, in the script this language writes them in.
     *
     * <p>Applied to everything numeric the page prints — prices, hours, distances, ratings, counts —
     * by every formatter below, so there is no path from a number to the markup that skips it.
     */
    String digits(String latin) {
        if (this == EN) {
            return latin;
        }
        StringBuilder out = new StringBuilder(latin.length());
        for (int i = 0; i < latin.length(); i++) {
            char c = latin.charAt(i);
            if (c >= '0' && c <= '9') {
                out.append((char) (0x0660 + (c - '0')));
            } else if (c == ',') {
                out.append('٬');
            } else if (c == '.') {
                out.append('٫');
            } else {
                out.append(c);
            }
        }
        return out.toString();
    }

    String number(long value) {
        return digits(String.format(Locale.ROOT, "%,d", value));
    }

    /** A dollar price, always to the cent: it is a price, and "$3.5" is not one. */
    String usd(BigDecimal amount) {
        String latin = String.format(Locale.ROOT, "%,.2f", amount.setScale(2, RoundingMode.HALF_UP));
        return this == AR ? digits(latin) + " $" : "$" + latin;
    }

    /** A lira face value: whole notes, never a fraction, because there is no coin to settle one. */
    String lbp(BigDecimal amount) {
        String latin = String.format(Locale.ROOT, "%,d", amount.longValue());
        return this == AR ? digits(latin) + " ل.ل." : latin + " LBP";
    }

    /** 24-hour, because that is how a shop writes its hours on its own door here. */
    String time(LocalTime at) {
        return digits(String.format(Locale.ROOT, "%02d:%02d", at.getHour(), at.getMinute()));
    }

    /** A delivery circle in kilometres, to one place, because metres are not how anybody says it. */
    String km(int metres) {
        String latin = String.format(Locale.ROOT, "%.1f", metres / 1000.0);
        return this == AR ? digits(latin) + " كم" : latin + " km";
    }

    String minutesRange(int from, int to) {
        return this == AR
                ? digits(from + "-" + to) + " دقيقة"
                : from + "-" + to + " min";
    }

    /** How long ago the merchant said what the lights were doing. */
    String ago(long minutes) {
        if (minutes < 60) {
            return this == AR
                    ? "قبل " + number(Math.max(1, minutes)) + " دقيقة"
                    : Math.max(1, minutes) + " min ago";
        }
        long hours = minutes / 60;
        return this == AR ? "قبل " + number(hours) + " ساعة" : hours + " h ago";
    }

    // ---------------------------------------------------------------- words

    private static final List<String> DAYS_EN = List.of(
            "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday");
    private static final List<String> DAYS_AR = List.of(
            "الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت", "الأحد");

    String day(int isoDay) {
        return (this == AR ? DAYS_AR : DAYS_EN).get(isoDay - 1);
    }

    String today() {
        return this == AR ? "اليوم" : "Today";
    }

    String tomorrow() {
        return this == AR ? "غدًا" : "tomorrow";
    }

    String openNow() {
        return this == AR ? "مفتوح الآن" : "Open now";
    }

    String closedNow() {
        return this == AR ? "مغلق الآن" : "Closed now";
    }

    String openUntil(LocalTime closesAt) {
        return this == AR ? "مفتوح حتى " + time(closesAt) : "Open until " + time(closesAt);
    }

    String opensToday(LocalTime at) {
        return this == AR ? "يفتح اليوم " + time(at) : "Opens today at " + time(at);
    }

    String opensTomorrow(LocalTime at) {
        return this == AR ? "يفتح غدًا " + time(at) : "Opens tomorrow at " + time(at);
    }

    String opensOn(int isoDay, LocalTime at) {
        return this == AR
                ? "يفتح " + day(isoDay) + " " + time(at)
                : "Opens " + day(isoDay) + " at " + time(at);
    }

    String closedAllDay() {
        return this == AR ? "مغلق" : "Closed";
    }

    String openingHours() {
        return this == AR ? "أوقات العمل" : "Opening hours";
    }

    String timesIn(String zone) {
        return this == AR
                ? "بتوقيت المتجر (" + zone + ")"
                // A typographic apostrophe, not the ASCII one. Every value that reaches the markup
                // goes through ShopPageHtml.esc, which escapes ' because these strings also land
                // in attributes — so the straight quote would read as "Shop&#39;s" in the source a
                // developer, a crawler's cache and a "view source" all see.
                : "Shop’s own time (" + zone + ")";
    }

    String power(Store.PowerStatus status) {
        return switch (status) {
            case MAINS -> this == AR ? "على الكهرباء" : "On mains";
            case GENERATOR -> this == AR ? "على المولّد" : "On generator";
            case DARK -> this == AR ? "لا كهرباء الآن" : "No power right now";
            case UNKNOWN -> "";
        };
    }

    String delivery() {
        return this == AR ? "التوصيل" : "Delivery";
    }

    String deliversWithin(int metres) {
        return this == AR ? "يوصّل ضمن " + km(metres) : "Delivers within " + km(metres);
    }

    String areasServed() {
        return this == AR ? "المناطق التي يوصّل إليها" : "Areas it delivers to";
    }

    String deliveryFee(BigDecimal fee, BigDecimal lbpFee) {
        String label = this == AR ? "رسوم التوصيل" : "Delivery fee";
        return label + " " + price(fee, lbpFee);
    }

    String minimumOrder(BigDecimal minimum, BigDecimal lbpMinimum) {
        String label = this == AR ? "الحد الأدنى للطلب" : "Minimum order";
        return label + " " + price(minimum, lbpMinimum);
    }

    String freeDelivery() {
        return this == AR ? "توصيل مجاني" : "Free delivery";
    }

    String noMinimum() {
        return this == AR ? "لا حد أدنى" : "No minimum order";
    }

    /** Dollars, and lira beside them when there is a rate to convert at. */
    String price(BigDecimal usd, BigDecimal lbp) {
        return lbp == null ? usd(usd) : usd(usd) + " · " + lbp(lbp);
    }

    String catalogue() {
        return this == AR ? "المعروضات" : "What they sell";
    }

    String otherItems() {
        return this == AR ? "أصناف أخرى" : "Other items";
    }

    /** The label on the search field, which only appears once the script has revealed it. */
    String searchThisShop() {
        return this == AR ? "ابحث في المتجر" : "Search this shop";
    }

    /**
     * The name of the bar of sections — its {@code aria-label} rather than a visible heading.
     *
     * <p>It was three words printed at the start of the row, on the one control that is short of
     * width. A screen reader reaches the bar as a navigation landmark and needs it named; a reader
     * looking at a row of section names does not need to be told they are section names.
     */
    String jumpTo() {
        return this == AR ? "انتقل إلى" : "Jump to";
    }

    /** The way back up a long menu, which is also the way back to the search box. */
    String backToTop() {
        return this == AR ? "العودة إلى أعلى القائمة" : "Back to the top of the menu";
    }

    /**
     * Shipped in the markup rather than built by the script, so it is in the reader's own language
     * without the script having to carry a second dictionary.
     */
    String nothingMatches() {
        return this == AR ? "لا يوجد صنف يطابق بحثك." : "Nothing in this shop matches that.";
    }

    String outOfStock() {
        return this == AR ? "غير متوفر" : "Out of stock";
    }

    /**
     * A shop is at its emptiest on the day it opens, which is the day this page matters most. It
     * says what is happening rather than leaving a reader to guess whether the page is broken.
     */
    String nothingListedYet() {
        return this == AR
                ? "لم يضف هذا المتجر أي صنف بعد."
                : "This shop has not listed anything here yet.";
    }

    String nothingListedHint() {
        return this == AR
                ? "أوقات العمل ومناطق التوصيل في الأعلى، وكل صنف يضيفه سيظهر هنا."
                : "Its hours and delivery area are above, and anything it adds shows up here.";
    }

    String andMoreInTheApp(int more) {
        return this == AR
                ? "و" + number(more) + " صنفًا آخر في التطبيق"
                : "and " + number(more) + " more in the app";
    }

    String rateNote(BigDecimal lbpPerUsd) {
        return this == AR
                ? "الأسعار بالدولار، والليرة محوّلة على " + number(lbpPerUsd.longValue())
                        + " ل.ل. للدولار"
                : "Prices in US dollars; lira converted at " + number(lbpPerUsd.longValue())
                        + " LBP to the dollar";
    }

    // ---------------------------------------------------------------- ordering at the table

    /**
     * How many of one thing, as it is printed on the count badge.
     *
     * <p>Through {@link #digits} like everything else numeric, so the Arabic page says "٢×" rather
     * than being the one surface on the platform that counts in Latin figures. The script prints
     * this string; it never counts with it, because it is a string.
     */
    String times(int qty) {
        return this == AR ? digits(String.valueOf(qty)) + "×" : qty + "×";
    }

    /** The pad's own heading. */
    String yourOrder() {
        return this == AR ? "طلبك" : "Your order";
    }

    String itemCount(int items) {
        if (this == AR) {
            return items == 1 ? "صنف واحد" : number(items) + " أصناف";
        }
        return items == 1 ? "1 item" : number(items) + " items";
    }

    /** The button on a menu row that puts it on the pad. */
    String add() {
        return this == AR ? "أضف" : "Add";
    }

    /**
     * What each of the two count buttons on a line does, for a screen reader.
     *
     * <p>A prefix, and the script puts the dish's own name after it — so a merchant's text reaches
     * the label through the DOM, where it is a string being assigned, and never through a string
     * this page built. Shipped once in an attribute rather than once per line.
     */
    String addOneMore() {
        return this == AR ? "أضف واحدًا من" : "Add one more";
    }

    String removeOne() {
        return this == AR ? "أزل واحدًا من" : "Remove one";
    }

    /** The label on the note a diner may leave on a line, and the example that explains it. */
    String noteOnALine() {
        return this == AR ? "ملاحظة للمطبخ" : "A note for the kitchen";
    }

    String noteExample() {
        return this == AR ? "بدون بصل" : "no onions";
    }

    String emptyPad() {
        return this == AR
                ? "لم تختر شيئًا بعد. أضف من القائمة أعلاه."
                : "Nothing chosen yet. Add something from the menu above.";
    }

    /** The strip at the foot of the screen that leads back to the pad. */
    String viewOrder() {
        return this == AR ? "عرض طلبك" : "Your order";
    }

    /**
     * The last line of the pad.
     *
     * <p>Not "Total (incl. VAT)", which is what the design asks for, and not a subtotal either.
     * There is one figure here — the food — because there is no delivery fee, no minimum, no
     * service charge and no tax anywhere in this: the diner pays the restaurant at the table, and
     * the platform is lending it an order pad. {@link #totalIsTheFood} says so beneath it.
     */
    String totalLine() {
        return this == AR ? "المجموع" : "Total";
    }

    String totalIsTheFood() {
        return this == AR
                ? "ما تطلبه فقط. تدفع للمطعم على الطاولة كالعادة."
                : "The food, and nothing else. You pay the restaurant at the table, as usual.";
    }

    /**
     * The table a printed code sent this diner to. Shown, and trusted for nothing else.
     *
     * <p>Only the word: the code itself comes out of the query string, is put after this by the
     * script and is drawn {@code dir="ltr"} — a table code is an identifier printed on a sticker,
     * "7" or "B12", and identifiers are not transliterated into another set of digits the way a
     * count or a price is.
     */
    String tableLabel() {
        return this == AR ? "طاولة" : "Table";
    }

    /** The one action: this goes to the kitchen. */
    String sendToKitchen() {
        return this == AR ? "أرسل إلى المطبخ" : "Send to the kitchen";
    }

    // ---------------------------------------------------------------- when it cannot be sent

    /**
     * This shop has not turned table ordering on.
     *
     * <p>The page still reads — it is the shop's menu and that is most of why anybody opened it —
     * and this is the whole of what changes: the pad is not there, and the reason is a sentence
     * rather than an absence a diner has to work out.
     */
    String orderWithTheStaff() {
        return this == AR
                ? "هذا المتجر لا يستقبل الطلبات من الطاولة عبر الإنترنت. اطلب من الموظفين."
                : "This shop does not take orders from the table online. Please order with the staff.";
    }

    /**
     * The page was opened without a table's code — from a link somebody shared, most likely.
     *
     * <p>Which is exactly the case that must not be allowed to send food to a kitchen: a shop's
     * page travels in WhatsApp, and a stranger on the other side of the city holding it is not
     * sitting at one of its tables.
     */
    String scanTheCodeOnYourTable() {
        return this == AR
                ? "امسح الرمز الموجود على طاولتك لتطلب من هنا."
                : "Scan the code on your table to order from here.";
    }

    String kitchenClosed() {
        return this == AR
                ? "المطبخ مغلق الآن، ولا يمكن إرسال الطلب."
                : "The kitchen is closed right now, so this cannot be sent.";
    }

    String somethingRanOut() {
        return this == AR
                ? "نفد صنف من طلبك. أزله لمتابعة الإرسال."
                : "Something on your order has run out. Remove it to send the rest.";
    }

    /** The shelf moved under a pad that was already in a browser. */
    String menuChanged() {
        return this == AR
                ? "تغيّرت قائمة المتجر، لذلك أُفرغ طلبك. أعد تحميل الصفحة وابدأ من جديد."
                : "This shop’s menu changed, so your order was cleared. Reload the page and start again.";
    }

    /**
     * When the server could not be asked what the order comes to.
     *
     * <p>The lines stay on the screen and the money does not appear at all. A page that filled the
     * gap with its own arithmetic would be showing somebody a figure nobody had agreed to, which is
     * the one thing this whole feature is built not to do.
     */
    String couldNotPrice() {
        return this == AR
                ? "تعذّر حساب المجموع الآن. حاول مرة أخرى بعد قليل."
                : "The total could not be worked out just now. Try again in a moment.";
    }

    /** What the diner with no script sees where the pad would have been. */
    String padNeedsScript() {
        return this == AR
                ? "يحتاج الطلب من الطاولة إلى JavaScript. القائمة والأسعار أعلاه كاملة بدونه."
                : "Ordering from the table needs JavaScript. The menu and the prices above are "
                        + "complete without it.";
    }

    // ---------------------------------------------------------------- once it has been sent

    /** On the button, while the order is on its way to the kitchen. */
    String sending() {
        return this == AR ? "يُرسل…" : "Sending…";
    }

    /** Over the rounds this phone has already sent from this table. */
    String alreadySent() {
        return this == AR ? "أرسلت من هذه الطاولة" : "Sent from this table";
    }

    /**
     * Where a sent round's ticket has got to, in the diner's words rather than the kitchen's.
     *
     * <p>Keyed by the order service's own status, and spelled here so that the browser holds no
     * dictionary and makes no decision: it looks up what the ticket says it is and prints the
     * sentence. Several statuses share a sentence, because a diner waiting for hummus does not
     * need to know the difference between a ticket the kitchen has accepted and one a rider would
     * have collected — and the ones that would mean something else on a delivery are spelled for
     * what they mean at a table. DELIVERED is food carried four metres.
     *
     * <p>Every status the lifecycle has is here. One that went unspelled would be a diner watching
     * a blank line while their order moved.
     */
    String ticketStates() {
        return this == AR
                ? "PLACED=أُرسل إلى المطبخ. لم يُستلم بعد.|ACCEPTED=المطبخ استلم طلبك."
                        + "|PREPARING=يُجهّز الآن.|READY=جاهز.|PICKED_UP=جاهز."
                        + "|DELIVERED=قُدّم. بالهناء والشفاء.|CANCELLED=أُلغي هذا الطلب. "
                        + "اسأل الموظفين."
                : "PLACED=Sent to the kitchen. Not picked up yet.|ACCEPTED=The kitchen has your "
                        + "order.|PREPARING=Being made now.|READY=Ready.|PICKED_UP=Ready."
                        + "|DELIVERED=Served. Enjoy your meal.|CANCELLED=This order was cancelled. "
                        + "Please ask the staff.";
    }

    /**
     * Why a send did not become a ticket, in words, keyed by what the order service answered.
     *
     * <p><strong>Every one of these is shown to the diner.</strong> A send that goes nowhere and
     * says nothing is the defect this page shipped with, and a silent disabled button is the same
     * defect wearing a different hat. So each refusal the endpoint can give has a sentence here,
     * including the two it is worth being honest about: {@code TOO_MANY}, which is the rate limit
     * and clears on its own — a second tap inside twenty seconds meets it, and so does a genuine
     * second round sent too quickly — and {@code FAILED}, which is everything else, including a
     * request that never left the phone.
     *
     * <p>{@code PRICE_CHANGED} says what happened and stops there: the new total is on the pad by
     * the time the diner reads it, because the page re-asks the quote rather than repeating a
     * figure the kitchen has already disagreed with. The page never re-sends on its own.
     */
    String sendRefusals() {
        return this == AR
                ? "TOO_MANY=أُرسلت طلبات كثيرة من هذه الطاولة. انتظر لحظة ثم أرسل مرة أخرى."
                        + "|REFUSED=لم يستطع المتجر استقبال هذا الطلب."
                        + "|PRICE_CHANGED=تغيّر السعر. راجع المجموع الجديد ثم أرسل مرة أخرى."
                        + "|FAILED=تعذّر إرسال طلبك الآن. حاول مرة أخرى أو اطلب من الموظفين."
                        + "|GONE=لم تعد هناك تحديثات لهذا الطلب. اسأل الموظفين عنه."
                : "TOO_MANY=That table has sent several orders just now. Wait a moment and send "
                        + "again.|REFUSED=The shop could not take this order."
                        + "|PRICE_CHANGED=The price changed. Check the new total and send again."
                        + "|FAILED=Your order could not be sent just now. Try again, or order with "
                        + "the staff.|GONE=There are no more updates for this order. Ask the staff "
                        + "about it.";
    }


    String howToOrder() {
        return this == AR ? "كيف تطلب" : "How to order";
    }

    String orderInTheApp() {
        return this == AR
                ? "الطلب من هذا المتجر يتم في تطبيق YouDrop."
                : "Orders from this shop are placed in the YouDrop app.";
    }

    String getTheApp() {
        return this == AR ? "حمّل التطبيق" : "Get the app";
    }

    /**
     * The honest sentence. A page with a shop's prices on it looks like a shop that takes money,
     * and a reader hunting for a basket that is not there has been misled by the layout.
     */
    String thisPageTakesNoOrders() {
        return this == AR
                ? "هذه الصفحة لا تستقبل الطلبات."
                : "This page cannot take an order itself.";
    }

    /** What the button actually hands back: {@code /app} is the Android build, as a download. */
    String androidDownload() {
        return this == AR ? "أندرويد · تحميل مباشر" : "Android · direct download";
    }

    /** The two listings that do not exist yet, said plainly rather than linked to nothing. */
    String storesSoon() {
        return this == AR
                ? "قريبًا على App Store و Google Play."
                : "Coming soon to the App Store and Google Play.";
    }

    String printThisPage() {
        return this == AR ? "رمز QR للطباعة" : "QR code to print";
    }

    String verifiedLocal() {
        return this == AR ? "دكانة موثّقة" : "Verified local shop";
    }

    String rated(BigDecimal rating, int count) {
        String stars = digits(rating.setScale(1, RoundingMode.HALF_UP).toPlainString());
        return this == AR
                ? stars + " من " + number(count) + " تقييم"
                : stars + " from " + number(count) + " ratings";
    }

    String vertical(Store.Vertical vertical, Store.ServiceCategory category) {
        if (vertical == Store.Vertical.SERVICES && category != null) {
            return switch (category) {
                case PRINTING -> this == AR ? "طباعة" : "Printing";
                case TAILORING -> this == AR ? "خياطة وتعديل" : "Tailoring";
                case REPAIRS -> this == AR ? "تصليح" : "Repairs";
                case PHOTOGRAPHY -> this == AR ? "تصوير" : "Photography";
                case CLEANING -> this == AR ? "تنظيف" : "Cleaning";
                case BEAUTY -> this == AR ? "تجميل" : "Beauty";
                case TUTORING -> this == AR ? "دروس خصوصية" : "Tutoring";
            };
        }
        return switch (vertical) {
            case RESTAURANT -> this == AR ? "مطعم" : "Restaurant";
            case COFFEE -> this == AR ? "قهوة" : "Coffee";
            case GROCERY -> this == AR ? "بقالة" : "Grocery";
            case CONVENIENCE -> this == AR ? "دكانة" : "Convenience";
            case PHARMACY -> this == AR ? "صيدلية" : "Pharmacy";
            case ELECTRONICS -> this == AR ? "إلكترونيات" : "Electronics";
            case FLOWERS_GIFTS -> this == AR ? "ورود وهدايا" : "Flowers and gifts";
            case SERVICES -> this == AR ? "خدمات" : "Services";
        };
    }

    /** The label on the link that switches language — written in the language it switches TO. */
    String switchLanguage() {
        return this == AR ? "English" : "العربية";
    }

    String onYouDrop() {
        return this == AR ? "على YouDrop" : "on YouDrop";
    }

    /**
     * The meta description a search result and a chat preview show.
     *
     * <p>Built from what the shop is and where it is rather than from its own tagline alone: a
     * tagline is often blank, and "Al Fakhry Press" with no second line is not a reason to tap.
     */
    String metaDescription(String name, String what, String neighbourhood) {
        if (neighbourhood == null || neighbourhood.isBlank()) {
            return this == AR
                    ? name + " — " + what + ". اطلب عبر YouDrop."
                    : name + " — " + what + ". Order on YouDrop.";
        }
        return this == AR
                ? name + " — " + what + " في " + neighbourhood + ". اطلب عبر YouDrop."
                : name + " — " + what + " in " + neighbourhood + ". Order on YouDrop.";
    }

    String notFoundTitle() {
        return this == AR ? "لا توجد صفحة هنا" : "No page here";
    }

    String notFoundBody() {
        return this == AR
                ? "هذا الرابط لا يشير إلى متجر على YouDrop."
                : "This link does not point at a shop on YouDrop.";
    }

    String backToSite() {
        return this == AR ? "الصفحة الرئيسية" : "Go to YouDrop";
    }
}
