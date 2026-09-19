package com.delivery.onboarding.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.CarrierRegistrationRepository;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;

/**
 * The delivery companies a rider can apply to, each with the region a rider joining it works in: one
 * rule for what the rider wizard shows and what the application records.
 *
 * <p><strong>The region is the company's zones, or else the regions it registered with.</strong> Order
 * Manager knows who is hiring and the names of each company's active coverage zones. A company that has
 * drawn no zone yet still said where it works when it applied to join — its application's
 * {@code details.coverage} (Beirut, Mount Lebanon, North, South, Bekaa) — and the owner decided
 * (2026-09) that such a company shows those. A company with neither, such as one the back office
 * registered by hand and so with no application at all, has no region, and the wizard shows a dash.
 *
 * <p><strong>Why here and not in Order Manager.</strong> The registration answer lives in this service,
 * on the application that created the company; Order Manager never held it. Moving it there would
 * take a second copy, a backfill across services and a change to the approval path, all to answer a
 * question this service can answer from its own table. So Order Manager keeps the zones and the hiring
 * rule, this class adds the registration answer, and both the app's list
 * ({@code GET /api/onboarding/hiring-companies}) and the region an application records come out of
 * {@link #resolve} — which is how the app shows exactly the region the server stores.
 *
 * <p>The link from a company to its application is the provider id the approval created
 * ({@link CarrierRegistrationRepository}). A company that applied more than once is read from its
 * newest application.
 *
 * <p><strong>Two readers, two freshnesses</strong>, as with the services form's lists. The form's list
 * is open to anybody, so it is served from memory for {@link #FORM_FRESH_FOR}; judging an application
 * ({@link #find}) is never answered from memory, because a company suspended a minute ago must not take
 * one more rider.
 */
@Component
public class HiringCompanies {

    /**
     * How long the open form's list is served from memory after a read. Each read is a call to Order
     * Manager, and the list is open to anybody: without this, every anonymous request would cost one.
     */
    public static final Duration FORM_FRESH_FOR = Duration.ofSeconds(30);

    /** The key a delivery company's application records the regions it works in under. */
    static final String COVERAGE = "coverage";

    /**
     * A company taking riders, with the region a rider joining it works in.
     *
     * @param regions its zone names, or else the regions it registered with; empty when it has neither
     */
    public record Company(UUID id, String name, List<String> regions) {
    }

    private final PlatformClient platform;
    private final CarrierRegistrationRepository registrations;
    private final Clock clock;

    /** The form's list and when it was read; null until the first read. Replaced whole. */
    private volatile Remembered remembered;

    private record Remembered(List<Company> companies, Instant readAt) {
    }

    @Autowired
    public HiringCompanies(PlatformClient platform, CarrierRegistrationRepository registrations) {
        this(platform, registrations, Clock.systemUTC());
    }

    /** With a clock the test moves, for the form's list. */
    HiringCompanies(PlatformClient platform, CarrierRegistrationRepository registrations,
                    Clock clock) {
        this.platform = platform;
        this.registrations = registrations;
        this.clock = clock;
    }

    /**
     * The list the open rider form offers, served from memory for {@link #FORM_FRESH_FOR} after a
     * read. A failed read is not remembered, so the next request asks again. Two requests arriving as
     * the list expires may both read it; that costs a duplicate read and nothing else, so nothing is
     * locked to prevent it.
     *
     * @throws PlatformClient.CompaniesUnavailableException when Order Manager cannot answer
     */
    public List<Company> forTheForm() {
        Instant now = clock.instant();
        Remembered last = remembered;
        if (last != null && now.isBefore(last.readAt().plus(FORM_FRESH_FOR))) {
            return last.companies();
        }
        List<Company> fresh = resolve(platform.hiringCompanies());
        remembered = new Remembered(fresh, now);
        return fresh;
    }

    /**
     * One company, when it is hiring right now, with its region: what an application naming it is
     * judged and recorded by. Never from memory.
     *
     * @throws PlatformClient.CompaniesUnavailableException when Order Manager cannot answer
     */
    public Optional<Company> find(UUID companyId) {
        return resolve(platform.hiringCompanies().stream()
                .filter(company -> company.id().equals(companyId))
                .toList())
                .stream()
                .findFirst();
    }

    /**
     * Each company with its region: its zones when it has any, else the regions its application
     * registered — read for every zone-less company in one query.
     */
    private List<Company> resolve(List<PlatformClient.HiringCompany> listed) {
        Map<UUID, List<String>> registered = registeredRegions(listed.stream()
                .filter(company -> company.regions().isEmpty())
                .map(PlatformClient.HiringCompany::id)
                .toList());
        return listed.stream()
                .map(company -> new Company(company.id(), company.name(),
                        company.regions().isEmpty()
                                ? registered.getOrDefault(company.id(), List.of())
                                : company.regions()))
                .toList();
    }

    /** The regions each company registered with, from the newest application that created it. */
    private Map<UUID, List<String>> registeredRegions(Collection<UUID> companyIds) {
        if (companyIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, OnboardingApplication> newest = new HashMap<>();
        for (OnboardingApplication application
                : registrations.findByKindAndProvisionedEntityIdIn(Kind.CARRIER, companyIds)) {
            newest.merge(application.getProvisionedEntityId(), application,
                    (kept, other) -> newer(other, kept) ? other : kept);
        }
        Map<UUID, List<String>> regions = new HashMap<>();
        newest.forEach((id, application) -> regions.put(id, coverageOf(application.getDetails())));
        return regions;
    }

    private static boolean newer(OnboardingApplication one, OnboardingApplication than) {
        Instant at = one.getCreatedAt();
        Instant other = than.getCreatedAt();
        return at != null && (other == null || at.isAfter(other));
    }

    /** The regions a delivery company's application registered, as names; nothing else counts as one. */
    static List<String> coverageOf(Map<String, Object> details) {
        if (details == null || !(details.get(COVERAGE) instanceof List<?> coverage)) {
            return List.of();
        }
        return coverage.stream()
                .filter(String.class::isInstance)
                .map(region -> ((String) region).trim())
                .filter(region -> !region.isEmpty())
                .distinct()
                .toList();
    }
}
