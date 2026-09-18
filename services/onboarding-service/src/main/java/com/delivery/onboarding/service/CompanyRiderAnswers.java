package com.delivery.onboarding.service;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.client.PlatformClient.HiringCompany;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;

/**
 * Where a rider applying to a delivery company is recorded as working: where the company works.
 *
 * <p><strong>The rider does not choose; the company's region is recorded.</strong> A rider who joins a
 * company rides where that company delivers, so the owner's rule is that they pick no area of their
 * own. The app shows them the company's region, read-only, and this records the same region on the
 * application as {@code details.companyRegions}: the names of the company's active coverage zones as
 * Order Manager's public list of who is hiring gives them when the application is judged — the list
 * the rider picked the company from. A company that has drawn no zone yet is recorded with an empty
 * list rather than with a guess.
 *
 * <p>Not the company's own registration answer ({@code details.coverage} on a delivery company's
 * application: Beirut, Mount Lebanon and so on). A company the back office registered has none, so
 * reading it would record different kinds of region depending on how a company joined. The owner may
 * still ask for it as the fallback for a company with no zones; {@link #regionOf} is the one place
 * that decision is made.
 *
 * <p><strong>What the app sent about a place is dropped, not refused</strong>: the free-text area, the
 * map pin, and the older keys a rider's region has been written under. Installed copies of the app
 * still send them for a company rider, and refusing those riders for answering a question the app used
 * to ask would lock them out until they updated. Dropping them keeps a reviewer, or the company's
 * roster, from reading an area the rider no longer chooses.
 *
 * <p><strong>The company must be hiring.</strong> Until now any id went through until approval, and an
 * application to a suspended company, a shop's own fleet or an id that names nothing sat in a queue
 * nobody reads. It is refused here with {@link CompanyAnswerException#NOT_HIRING}, judged by the same
 * list the app offered, so the rider chooses again.
 *
 * <p>A rider riding for YouDrop itself names no company, costs no call, and keeps the area and pin they
 * chose. {@code companyRegions} is only ever written here, so a copy of it sent with any other
 * application is dropped.
 *
 * <p>Not a bean of its own: {@link ServiceProviderAnswers} holds one, because everything the intake
 * records has to come through that one check first — see {@link ServiceProviderAnswers.Checked}.
 */
public final class CompanyRiderAnswers {

    /** The details key the company's region is recorded under. */
    static final String COMPANY_REGIONS = "companyRegions";

    /**
     * Every key a rider's place has been sent under: the wizard's free-text area and map pin, and the
     * older shapes the carrier roster still reads a region from.
     */
    static final List<String> PLACE_KEYS = List.of(
            "preferredArea", "workLatitude", "workLongitude", "workRegion", "region", "city", "area");

    /** A refusal about the company a rider named, coded like every refusal the app translates. */
    public static class CompanyAnswerException extends AccountApplicationService.AccountRuleException {

        /** Not on Order Manager's list of who is hiring: unknown, suspended, or not a company that hires. */
        public static final String NOT_HIRING = "company-not-hiring";

        public CompanyAnswerException(String code, String message) {
            super(code, message);
        }
    }

    private final PlatformClient platform;

    CompanyRiderAnswers(PlatformClient platform) {
        this.platform = platform;
    }

    /**
     * Whether this is a rider naming a delivery company: the one application judged here, and so the
     * one whose check waits on Order Manager.
     */
    static boolean namesACompany(Kind kind, UUID targetProviderId) {
        return kind == Kind.RIDER && targetProviderId != null;
    }

    /**
     * The details to record.
     *
     * <p>For a rider naming a company, the company is looked up — which waits on Order Manager, so call
     * this with no transaction open — and the details come back with its region in place of any place
     * the app sent. For any other application they come back as sent, the very same map, unless they
     * carry a {@code companyRegions} this class did not write.
     *
     * @throws CompanyAnswerException when the company named is not hiring
     * @throws PlatformClient.CompaniesUnavailableException when Order Manager cannot answer — nothing
     *         was judged, so the applicant retries rather than chooses again
     */
    Map<String, Object> checked(Kind kind, UUID targetProviderId, Map<String, Object> details) {
        if (!namesACompany(kind, targetProviderId)) {
            if (details == null || !details.containsKey(COMPANY_REGIONS)) {
                return details;
            }
            Map<String, Object> unclaimed = new LinkedHashMap<>(details);
            unclaimed.remove(COMPANY_REGIONS);
            return unclaimed;
        }

        HiringCompany company = platform.hiringCompanies().stream()
                .filter(candidate -> candidate.id().equals(targetProviderId))
                .findFirst()
                .orElseThrow(() -> new CompanyAnswerException(CompanyAnswerException.NOT_HIRING,
                        "That delivery company is not taking riders right now. Choose another "
                                + "company, or ride for YouDrop"));

        Map<String, Object> recorded = details == null
                ? new LinkedHashMap<>()
                : new LinkedHashMap<>(details);
        PLACE_KEYS.forEach(recorded::remove);
        recorded.put(COMPANY_REGIONS, regionOf(company));
        return recorded;
    }

    /**
     * The region recorded for a company: the names of its active zones, and an empty list when it has
     * drawn none. The place a fallback to the company's registration answer would go, if the owner
     * asks for one.
     */
    private static List<String> regionOf(HiringCompany company) {
        return company.regions();
    }
}
