package com.delivery.onboarding.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.client.PlatformClient.ServiceArea;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;

/**
 * What an application to offer services must say, and how it is shown back.
 *
 * <p>A services provider — a print shop, a tailor, a repairer — applies as a MERCHANT whose
 * {@code details.businessType} is {@code SERVICES}, with the service category they offer and the
 * area they work in (owner default 5, docs/figma-services-designs.md). There is no new kind, so the
 * application shares the merchant queue, the merchant auto-approval switch and the merchant
 * documents. What this class adds is the one promise a free-form document cannot make on its own:
 * that those answers are real, so the back office can show them and the provider's app can open the
 * shop from them.
 *
 * <p><strong>The category must be open, and Product Service is asked which are.</strong> Product
 * Service owns the taxonomy and the switch ({@code delivery.product.services.enabled-categories},
 * read per call) and refuses to open a shop in a closed category. A copy of that list here would
 * drift the first time somebody opened a category on one side only — and the applicant who fell in
 * the gap would be approved into a category their shop could never be opened in. So there is no
 * copy: every services application asks, at the moment it is judged. The form asks too, through
 * {@link #options()}, but may be answered from the last half minute's lists — see
 * {@link #OPTIONS_FRESH_FOR} for why that is safe for an offer when it would not be for a judgement.
 *
 * <p><strong>Asked before the intake's transaction, never inside it.</strong> {@link #checked} waits
 * on Product Service, so the two front doors — {@link OnboardingService#submit} and
 * {@link AccountApplicationService#apply} — call it with no transaction open and hand
 * {@link ApplicationIntake} the {@link Checked} result, the only form it records. See
 * {@link ApplicationIntake} for the connection pool that used to be held across that wait.
 *
 * <p><strong>The area must be a live delivery zone</strong>, and it is recorded under the zone's own
 * name rather than whatever label the client sent, because the back office shows it and the
 * provider's shop is filed under it.
 *
 * <p>Nothing here touches an application that is not a services one. A shop, a rider and a delivery
 * company go through exactly as before, and Product Service is never asked about them.
 *
 * <p>One exception rides through the same door, and only because it is the same kind of check: a
 * rider naming a delivery company is judged against Order Manager — the company must be hiring, and
 * its region is recorded in place of an area the rider chose. That rule is
 * {@link CompanyRiderAnswers}'s; it is reached from {@link #checked} because {@link Checked} is the
 * only form the intake records, so a front door cannot skip it. For the same reason a delivery
 * company's own application has its coverage kept here to the regions the company form offers
 * ({@link HiringCompanies#withRegisteredCoverage}): riders are shown that coverage as the company's
 * region.
 */
@Component
public class ServiceProviderAnswers {

    /** The businessType that makes a shop's application a services provider's. */
    public static final String SERVICES = "SERVICES";

    /**
     * How long the signup form's two lists are served from memory after a read.
     *
     * <p>{@code GET /api/onboarding/service-options} is open to anybody, and each answer used to be
     * two reads of Product Service with the platform's own token: every anonymous request cost two
     * remote calls, and with Product Service slow, an onboarding request thread for up to ten
     * seconds. Half a minute makes that one pair of reads per half minute, however many people ask.
     *
     * <p>It is safe because the form only offers. The application is judged by {@link #checked},
     * which is never answered from memory: a category closed a moment ago can still be picked, and is
     * then refused with {@code service-category-closed}, which takes the applicant back to the form
     * to choose again. A category opened a moment ago is on the form within the half minute.
     */
    public static final Duration OPTIONS_FRESH_FOR = Duration.ofSeconds(30);

    static final String BUSINESS_TYPE = "businessType";
    static final String SERVICE_CATEGORY = "serviceCategory";
    static final String AREA = "area";
    static final String ZONE_ID = "zoneId";
    static final String LABEL = "label";

    private final PlatformClient platform;
    private final Clock clock;

    /**
     * The rider's half of the same check: a rider naming a delivery company has that company's region
     * recorded, and is refused when the company is not hiring. Held here because {@link #checked} is
     * the one check both front doors make before the intake, and the only maker of what it records.
     */
    private final CompanyRiderAnswers companyRiders;

    /** The form's lists and when they were read; null until the first read. Replaced whole. */
    private volatile CachedOptions cachedOptions;

    private record CachedOptions(Options options, Instant readAt) {
    }

    @Autowired
    public ServiceProviderAnswers(PlatformClient platform, HiringCompanies hiring) {
        this(platform, hiring, Clock.systemUTC());
    }

    /** With a clock the test moves, for the form's lists. */
    ServiceProviderAnswers(PlatformClient platform, HiringCompanies hiring, Clock clock) {
        this.platform = platform;
        this.clock = clock;
        this.companyRiders = new CompanyRiderAnswers(hiring);
    }

    /**
     * A services answer the applicant has to change.
     *
     * <p>Coded like the signed-in path's own refusals, because these are checked on both front doors
     * and the app translates the code on either. The codes are part of the API: rename one and the
     * app quietly falls back to the English message.
     */
    public static class ServiceAnswerException extends AccountApplicationService.AccountRuleException {

        /** businessType SERVICES on an application that is not a shop's. */
        public static final String NOT_A_SHOP = "service-not-a-shop";

        public static final String CATEGORY_MISSING = "service-category-missing";

        /** Not open right now — or not a category at all, which reads the same to an applicant. */
        public static final String CATEGORY_CLOSED = "service-category-closed";

        public static final String AREA_MISSING = "service-area-missing";

        /** A zone id that is not a live delivery zone, typically one retired since the form loaded. */
        public static final String AREA_UNKNOWN = "service-area-unknown";

        public ServiceAnswerException(String code, String message) {
            super(code, message);
        }
    }

    /**
     * What an applicant is shown about their own services answers.
     *
     * <p>The category and the area and nothing else from {@code details}, which can hold bank
     * details. Enough for the provider's app to open the shop the application describes.
     */
    public record Summary(String category, String zoneId, String area) {
    }

    /** What the services signup form offers: the open categories and the areas to pick from. */
    public record Options(List<String> categories, List<ServiceArea> areas) {
    }

    /**
     * Details that have been through {@link #checked} — the only form {@link ApplicationIntake}
     * records.
     *
     * <p>A type rather than a map because the check moved out of the intake, to before its
     * transaction, and a check its callers make could have become a rule each front door has to
     * remember. It cannot: nothing but {@link #checked} makes one of these, so a front door that
     * skipped the check would not compile.
     */
    public static final class Checked {

        private final Map<String, Object> details;

        private Checked(Map<String, Object> details) {
            this.details = details;
        }

        /**
         * A services application's details in canonical form; a rider's naming a delivery company
         * with the company's region in place of any place the app sent; a delivery company's with
         * its coverage kept to the regions its form offers; any other application's exactly as sent
         * — less any {@code companyRegions}, which only {@link CompanyRiderAnswers} writes.
         */
        public Map<String, Object> details() {
            return details;
        }
    }

    /** Whether these details say the application is to offer services. */
    public static boolean isServices(Map<String, Object> details) {
        return details != null && details.get(BUSINESS_TYPE) instanceof String type
                && SERVICES.equalsIgnoreCase(type.trim());
    }

    /**
     * Whether these details say which business the application is for at all — SERVICES or a goods
     * type. The shop wizard and the services signup always do. A request that only resumes the
     * application already on file, as the Google sign-in's does, sends no details.
     */
    public static boolean namesBusinessType(Map<String, Object> details) {
        return details != null && details.get(BUSINESS_TYPE) instanceof String type
                && !type.isBlank();
    }

    /**
     * The open categories and the areas, for the signup form — the same two lists
     * {@link #checked} judges against, so the form offers what the intake would accept.
     *
     * <p>Served from memory for {@link #OPTIONS_FRESH_FOR} after a read. A failed read is not
     * remembered, so the next request asks again. Two requests arriving as the lists expire may both
     * read them; that only costs a duplicate read, so nothing is locked to prevent it — a lock would
     * have every request queue behind a slow Product Service instead.
     *
     * @throws PlatformClient.CatalogUnavailableException when Product Service cannot answer
     */
    public Options options() {
        Instant now = clock.instant();
        CachedOptions cached = cachedOptions;
        if (cached != null && now.isBefore(cached.readAt().plus(OPTIONS_FRESH_FOR))) {
            return cached.options();
        }
        Options fresh = new Options(platform.openServiceCategories(), platform.serviceAreas());
        cachedOptions = new CachedOptions(fresh, now);
        return fresh;
    }

    /**
     * The details to record.
     *
     * <p>For a services application, checked and put in canonical form: the business type and
     * category upper-cased, the area named as its zone is named. The refusals that need nothing from
     * Product Service come first, and the zones are only read once the category is known to be open.
     *
     * <p>For a rider naming a delivery company, the company's region in place of any place the app
     * sent, and a refusal when the company is not hiring — see {@link CompanyRiderAnswers}. For a
     * delivery company, its coverage kept to the regions its form offers — see
     * {@link HiringCompanies#withRegisteredCoverage}. Any other application's details are recorded as
     * sent. None keeps a {@code companyRegions} it sent, a services application included: that key
     * is the region a company rider was shown, and only {@link CompanyRiderAnswers} writes it.
     *
     * <p>Never answered from memory, unlike {@link #options()}: this is the judgement, and it has to
     * be the one Product Service, or Order Manager, would give now. It waits on them, so call it with
     * no transaction open.
     *
     * @param targetProviderId the delivery company a rider applies to; null for everybody else
     * @throws ServiceAnswerException for an answer the applicant has to change
     * @throws CompanyRiderAnswers.CompanyAnswerException when the company a rider named is not hiring
     * @throws PlatformClient.CatalogUnavailableException when Product Service cannot answer — nothing
     *         was judged, so the applicant retries rather than changes an answer
     * @throws PlatformClient.CompaniesUnavailableException when Order Manager cannot answer, likewise
     */
    public Checked checked(Kind kind, Map<String, Object> details, UUID targetProviderId) {
        if (!isServices(details)) {
            return new Checked(companyRiders.checked(kind, targetProviderId,
                    HiringCompanies.withRegisteredCoverage(kind, details)));
        }
        if (kind != Kind.MERCHANT) {
            throw new ServiceAnswerException(ServiceAnswerException.NOT_A_SHOP,
                    "Only a shop can apply to offer services");
        }

        String category = text(details.get(SERVICE_CATEGORY)).toUpperCase(Locale.ROOT);
        if (category.isEmpty()) {
            throw new ServiceAnswerException(ServiceAnswerException.CATEGORY_MISSING,
                    "Choose the service you offer");
        }
        UUID zoneId = zoneIdOf(details.get(AREA));
        if (zoneId == null) {
            throw new ServiceAnswerException(ServiceAnswerException.AREA_MISSING,
                    "Choose the area your business is in");
        }

        if (!platform.openServiceCategories().contains(category)) {
            throw new ServiceAnswerException(ServiceAnswerException.CATEGORY_CLOSED,
                    "YouDrop is not taking applications for that service yet");
        }
        ServiceArea area = platform.serviceAreas().stream()
                .filter(candidate -> candidate.zoneId().equals(zoneId))
                .findFirst()
                .orElseThrow(() -> new ServiceAnswerException(ServiceAnswerException.AREA_UNKNOWN,
                        "That area is no longer on YouDrop's list. Choose your area again"));

        Map<String, Object> canonical = new LinkedHashMap<>(details);
        // Copied as sent otherwise, so a region a client claimed for itself would survive here when
        // CompanyRiderAnswers drops it from every other application.
        canonical.remove(CompanyRiderAnswers.COMPANY_REGIONS);
        canonical.put(BUSINESS_TYPE, SERVICES);
        canonical.put(SERVICE_CATEGORY, category);
        canonical.put(AREA, Map.of(ZONE_ID, area.zoneId().toString(), LABEL, area.name()));
        return new Checked(canonical);
    }

    /** The services answers as the applicant's own receipt shows them; null for any other application. */
    public static Summary summaryOf(Map<String, Object> details) {
        if (!isServices(details)) {
            return null;
        }
        String zoneId = null;
        String label = null;
        if (details.get(AREA) instanceof Map<?, ?> area) {
            zoneId = emptyToNull(text(area.get(ZONE_ID)));
            label = emptyToNull(text(area.get(LABEL)));
        }
        return new Summary(emptyToNull(text(details.get(SERVICE_CATEGORY))), zoneId, label);
    }

    private static UUID zoneIdOf(Object area) {
        if (!(area instanceof Map<?, ?> answer)) {
            return null;
        }
        String id = text(answer.get(ZONE_ID));
        if (id.isEmpty()) {
            return null;
        }
        try {
            return UUID.fromString(id);
        } catch (IllegalArgumentException notAnId) {
            return null;
        }
    }

    private static String text(Object value) {
        return value instanceof String s ? s.trim() : "";
    }

    private static String emptyToNull(String value) {
        return value.isEmpty() ? null : value;
    }
}
