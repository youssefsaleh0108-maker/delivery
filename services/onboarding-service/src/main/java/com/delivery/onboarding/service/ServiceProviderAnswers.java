package com.delivery.onboarding.service;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

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
 * copy: every services application asks, and so does the form, through {@link #options()}.
 *
 * <p><strong>The area must be a live delivery zone</strong>, and it is recorded under the zone's own
 * name rather than whatever label the client sent, because the back office shows it and the
 * provider's shop is filed under it.
 *
 * <p>Nothing here touches an application that is not a services one. A shop, a rider and a delivery
 * company go through exactly as before, and Product Service is never asked about them.
 */
@Component
public class ServiceProviderAnswers {

    /** The businessType that makes a shop's application a services provider's. */
    public static final String SERVICES = "SERVICES";

    static final String BUSINESS_TYPE = "businessType";
    static final String SERVICE_CATEGORY = "serviceCategory";
    static final String AREA = "area";
    static final String ZONE_ID = "zoneId";
    static final String LABEL = "label";

    private final PlatformClient platform;

    public ServiceProviderAnswers(PlatformClient platform) {
        this.platform = platform;
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

    /** Whether these details say the application is to offer services. */
    public static boolean isServices(Map<String, Object> details) {
        return details != null && details.get(BUSINESS_TYPE) instanceof String type
                && SERVICES.equalsIgnoreCase(type.trim());
    }

    /**
     * The open categories and the areas, for the signup form — the same two lists
     * {@link #checked} judges against, so the form never offers an answer the intake would refuse.
     *
     * @throws PlatformClient.CatalogUnavailableException when Product Service cannot answer
     */
    public Options options() {
        return new Options(platform.openServiceCategories(), platform.serviceAreas());
    }

    /**
     * The details to record.
     *
     * <p>Unchanged for any other application. For a services one, checked and put in canonical form:
     * the business type and category upper-cased, the area named as its zone is named. The refusals
     * that need nothing from Product Service come first, and the zones are only read once the
     * category is known to be open.
     *
     * @throws ServiceAnswerException for an answer the applicant has to change
     * @throws PlatformClient.CatalogUnavailableException when Product Service cannot answer — nothing
     *         was judged, so the applicant retries rather than changes an answer
     */
    public Map<String, Object> checked(Kind kind, Map<String, Object> details) {
        if (!isServices(details)) {
            return details;
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
        canonical.put(BUSINESS_TYPE, SERVICES);
        canonical.put(SERVICE_CATEGORY, category);
        canonical.put(AREA, Map.of(ZONE_ID, area.zoneId().toString(), LABEL, area.name()));
        return canonical;
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
