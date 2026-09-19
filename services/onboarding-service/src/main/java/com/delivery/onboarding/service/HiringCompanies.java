package com.delivery.onboarding.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

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
 * {@code details.coverage}, some of the five regions of {@link #REGISTRATION_REGIONS} — and the owner
 * decided (2026-09) that such a company shows those. A company with neither, such as one the back
 * office registered by hand and so with no application at all, has no region, and the wizard shows a
 * dash.
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
 * is open to anybody, so it is served from memory for {@link #FORM_FRESH_FOR}, and from the last good
 * read while Order Manager cannot answer; judging an application ({@link #find}) is never answered from
 * memory, because a company suspended a minute ago must not take one more rider.
 */
@Component
public class HiringCompanies {

    /**
     * How long the open form's list is served from memory after a read. Each read is a call to Order
     * Manager, and the list is open to anybody: without this, every anonymous request would cost one.
     */
    public static final Duration FORM_FRESH_FOR = Duration.ofSeconds(30);

    /**
     * How long a failed read of the open form's list is remembered: for this long after Order Manager
     * failed to answer, nobody asks it again for the form, and the form is served the last list read —
     * or, when there has never been one, told at once that there is none.
     *
     * <p>A failed read used to be forgotten, so while Order Manager was down or slow every anonymous
     * request asked it again and held a request thread for the whole bounded wait, up to five seconds
     * (see PlatformClient's {@code boundedWait}): a few callers asking twenty times a second could tie
     * up a couple of hundred threads. A few seconds is short enough that a recovered Order Manager is
     * back on the form almost at once.
     */
    public static final Duration FORM_FAILURE_REMEMBERED_FOR = Duration.ofSeconds(5);

    /**
     * The regions a delivery company can register with, and the only names ever shown as one: the
     * carrier wizard's coverage chips, spelled as it sends them (mobile_app
     * {@code partner_application_screen.dart}, {@code _lebanonAreas}), which the app then shows in the
     * reader's language.
     *
     * <p><strong>Why nothing else counts.</strong> {@code details.coverage} is written by whoever fills
     * in the open company form — nobody signed in — and what it says goes out on the open hiring list
     * to anybody who asks, and onto the application of every rider who joins that company. Carrier
     * auto-approval can be switched on, and then no person reads the application before that happens,
     * so a free-text "region" would be a way to publish any words at all on YouDrop's own list. The
     * wizard has only ever offered these five, so keeping to them loses no real answer.
     */
    public static final List<String> REGISTRATION_REGIONS =
            List.of("Beirut", "Mount Lebanon", "North", "South", "Bekaa");

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

    /** The form's list and when it was read; null until the first good read. Replaced whole. */
    private volatile Remembered remembered;

    /** The form's last failed read and when it failed; null once a read succeeds. Replaced whole. */
    private volatile Failed failed;

    /** Whether a request is asking Order Manager for the form's list right now. */
    private final AtomicBoolean reading = new AtomicBoolean();

    private record Remembered(List<Company> companies, Instant readAt) {
    }

    private record Failed(PlatformClient.CompaniesUnavailableException cause, Instant at) {
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
     * read.
     *
     * <p><strong>Order Manager is only ever waited on by one request at a time, and never again
     * within {@link #FORM_FAILURE_REMEMBERED_FOR} of failing.</strong> Any other request meanwhile is
     * answered at once from the last list read, however old — it is only an offer: the application is
     * judged by {@link #find}, afresh, and a company that has stopped hiring since is refused there by
     * name and the rider chooses again. Only before any read has ever succeeded is there nothing to
     * offer, and then the answer is "try again" at once rather than a thread held behind Order Manager's
     * wait. Nothing queues on a lock: the one request that does ask is the only one waiting.
     *
     * @throws PlatformClient.CompaniesUnavailableException when Order Manager cannot answer and no
     *         list has ever been read
     */
    public List<Company> forTheForm() {
        Instant now = clock.instant();
        Remembered last = remembered;
        if (last != null && now.isBefore(last.readAt().plus(FORM_FRESH_FOR))) {
            return last.companies();
        }
        Failed failure = failed;
        boolean failedJustNow = failure != null
                && now.isBefore(failure.at().plus(FORM_FAILURE_REMEMBERED_FOR));
        if (failedJustNow || !reading.compareAndSet(false, true)) {
            return lastReadOrUnavailable(last, failure);
        }
        try {
            List<Company> fresh = resolve(platform.hiringCompanies());
            remembered = new Remembered(fresh, now);
            failed = null;
            return fresh;
        } catch (PlatformClient.CompaniesUnavailableException e) {
            // Timed from when the read gave up, not from when it started: a read that waited out the
            // whole bounded wait would otherwise be remembered for no time at all.
            failed = new Failed(e, clock.instant());
            if (last != null) {
                return last.companies();
            }
            throw e;
        } finally {
            reading.set(false);
        }
    }

    /** The last list read, however old; when there has never been one, "try again". */
    private static List<Company> lastReadOrUnavailable(Remembered last, Failed failure) {
        if (last != null) {
            return last.companies();
        }
        throw new PlatformClient.CompaniesUnavailableException(
                "We could not read which delivery companies are hiring just now. Please try again "
                        + "in a moment.",
                failure == null ? null : failure.cause());
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

    /**
     * The regions a delivery company's application registered, in the order it listed them: only the
     * names of {@link #REGISTRATION_REGIONS}, each once. Anything else is dropped — see there for why.
     */
    static List<String> coverageOf(Map<String, Object> details) {
        if (details == null || !(details.get(COVERAGE) instanceof List<?> coverage)) {
            return List.of();
        }
        return coverage.stream()
                .filter(String.class::isInstance)
                .map(region -> ((String) region).trim())
                .filter(REGISTRATION_REGIONS::contains)
                .distinct()
                .toList();
    }

    /**
     * An application's details as they are recorded: a delivery company's with its coverage kept to
     * {@link #REGISTRATION_REGIONS} by {@link #coverageOf}, and anything else in it dropped. Any other
     * application's — and a company's that says nothing about coverage — come back as sent, the very
     * same map.
     *
     * <p>Dropped rather than refused. The wizard only offers the five, so no installed app ever sends
     * anything else and none is refused for it; whatever else arrives did not come from the form, and
     * refusing it would only tell its sender what to change. {@link #coverageOf} keeps to the same rule
     * on the way out, for the applications recorded before this.
     */
    static Map<String, Object> withRegisteredCoverage(Kind kind, Map<String, Object> details) {
        if (kind != Kind.CARRIER || details == null || !details.containsKey(COVERAGE)) {
            return details;
        }
        Map<String, Object> recorded = new LinkedHashMap<>(details);
        recorded.put(COVERAGE, coverageOf(details));
        return recorded;
    }
}
