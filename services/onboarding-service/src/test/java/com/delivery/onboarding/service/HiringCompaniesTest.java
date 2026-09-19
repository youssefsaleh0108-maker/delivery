package com.delivery.onboarding.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.stubbing.Answer;
import org.springframework.data.repository.query.parser.PartTree;
import org.springframework.test.util.ReflectionTestUtils;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.CarrierRegistrationRepository;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Who is hiring, and the region a rider joining each company works in.
 *
 * <p>The rule (owner, 2026-09): a company's zones; else, for a company with none, the regions it
 * registered with; else nothing. Pinned with Order Manager and the applications table as stand-ins,
 * including the costs — one read of the applications for every zone-less company at once and none when
 * every company has zones; the open form's list from memory for half a minute, and from the last good
 * read while Order Manager cannot answer, with one request at most waiting on it; judging an
 * application never from memory. And what an anonymous company form can put on that open list: only
 * the five regions the form offers.
 */
@DisplayName("who is hiring, and where each company works")
class HiringCompaniesTest {

    private static final UUID SWIFT = UUID.fromString("8a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d");
    private static final UUID FRESH = UUID.fromString("1f2e3d4c-5b6a-4978-8695-a4b3c2d1e0f9");
    private static final UUID BY_HAND = UUID.fromString("5c4b3a29-1807-4f6e-9d5c-4b3a29180706");

    private PlatformClient platform;
    private CarrierRegistrationRepository registrations;
    private MovableClock clock;
    private HiringCompanies hiring;

    @BeforeEach
    void setUp() {
        platform = mock(PlatformClient.class);
        registrations = mock(CarrierRegistrationRepository.class);
        clock = new MovableClock();
        hiring = new HiringCompanies(platform, registrations, clock);
    }

    /** Order Manager's list: Swift has zones, Fresh has none, and By Hand has none and no application. */
    private void orderManagerLists() {
        when(platform.hiringCompanies()).thenReturn(List.of(
                new PlatformClient.HiringCompany(SWIFT, "Swift Couriers", List.of("Achrafieh", "Hamra")),
                new PlatformClient.HiringCompany(FRESH, "Fresh Fleet", List.of()),
                new PlatformClient.HiringCompany(BY_HAND, "By Hand Deliveries", List.of())));
    }

    /** The delivery-company application that created this company, set up and linked to it. */
    private static OnboardingApplication registered(UUID company, Object coverage, Instant at) {
        Map<String, Object> details = new HashMap<>();
        details.put("companyType", "Registered LLC");
        if (coverage != null) {
            details.put("coverage", coverage);
        }
        OnboardingApplication application = new OnboardingApplication(Kind.CARRIER, "Fresh Fleet",
                "Rami Aoun", "rami@fresh.example", Instant.now(), null, null, null, details, null);
        application.provisionedAs("owner-" + company, company);
        ReflectionTestUtils.setField(application, "createdAt", at);
        return application;
    }

    private void registrationsHold(OnboardingApplication... applications) {
        when(registrations.findByKindAndProvisionedEntityIdIn(eq(Kind.CARRIER), any()))
                .thenReturn(Arrays.asList(applications));
    }

    private static List<String> regionsOf(List<HiringCompanies.Company> companies, UUID id) {
        return companies.stream().filter(company -> company.id().equals(id)).findFirst()
                .orElseThrow(() -> new AssertionError(id + " is not listed")).regions();
    }

    @Test
    @DisplayName("a company's zones are its region; one with none shows what it registered with; one with neither, nothing")
    void zones_else_registration_else_nothing() {
        orderManagerLists();
        registrationsHold(registered(FRESH, List.of("Beirut", "Mount Lebanon"),
                Instant.parse("2026-08-01T09:00:00Z")));

        List<HiringCompanies.Company> companies = hiring.forTheForm();

        assertThat(companies).extracting(HiringCompanies.Company::name)
                .containsExactly("Swift Couriers", "Fresh Fleet", "By Hand Deliveries");
        assertThat(regionsOf(companies, SWIFT)).containsExactly("Achrafieh", "Hamra");
        assertThat(regionsOf(companies, FRESH)).containsExactly("Beirut", "Mount Lebanon");
        assertThat(regionsOf(companies, BY_HAND)).isEmpty();
    }

    @Test
    @DisplayName("the applications are read once, for the zone-less companies only, and not at all when every company has zones")
    void one_read_for_the_zone_less() {
        orderManagerLists();

        hiring.forTheForm();

        verify(registrations).findByKindAndProvisionedEntityIdIn(eq(Kind.CARRIER), argThat(ids ->
                ids.size() == 2 && ids.containsAll(List.of(FRESH, BY_HAND))));

        CarrierRegistrationRepository untouched = mock(CarrierRegistrationRepository.class);
        PlatformClient zonesOnly = mock(PlatformClient.class);
        when(zonesOnly.hiringCompanies()).thenReturn(List.of(
                new PlatformClient.HiringCompany(SWIFT, "Swift Couriers", List.of("Hamra"))));
        new HiringCompanies(zonesOnly, untouched, clock).forTheForm();
        verifyNoInteractions(untouched);
    }

    @Test
    @DisplayName("a company that applied twice shows what its newest application registered")
    void the_newest_application_wins() {
        orderManagerLists();
        registrationsHold(
                registered(FRESH, List.of("North"), Instant.parse("2026-03-01T09:00:00Z")),
                registered(FRESH, List.of("South", "Bekaa"), Instant.parse("2026-08-01T09:00:00Z")));

        assertThat(regionsOf(hiring.forTheForm(), FRESH)).containsExactly("South", "Bekaa");
    }

    @Test
    @DisplayName("only names count as regions: blanks, repeats and anything that is not a name are dropped")
    void registered_regions_are_names_only() {
        List<Object> messy = new ArrayList<>(Arrays.asList(" Beirut ", "", "   ", 7, null, "Beirut", "North"));
        orderManagerLists();
        registrationsHold(
                registered(FRESH, messy, Instant.parse("2026-08-01T09:00:00Z")),
                registered(BY_HAND, "Beirut", Instant.parse("2026-08-01T09:00:00Z")));

        List<HiringCompanies.Company> companies = hiring.forTheForm();

        assertThat(regionsOf(companies, FRESH)).containsExactly("Beirut", "North");
        assertThat(regionsOf(companies, BY_HAND)).isEmpty();
    }

    /**
     * The coverage answer comes from the open company form, which nobody has to sign in to, and what
     * it says is shown to anybody on this list — with carrier auto-approval on, before any person has
     * read it. Only the five regions the form offers ever reach the list.
     */
    @Test
    @DisplayName("only the five regions the company form offers count: free text an applicant sent never reaches the open list")
    void only_the_forms_regions_are_shown() {
        orderManagerLists();
        registrationsHold(
                registered(FRESH, List.of("Mount Lebanon", "Cash jobs daily, call 70 123 456",
                        "<b>Best pay in town</b>", "Achrafieh", "beirut", "South"),
                        Instant.parse("2026-08-01T09:00:00Z")),
                registered(BY_HAND, List.of("Anything we like"), Instant.parse("2026-08-01T09:00:00Z")));

        List<HiringCompanies.Company> companies = hiring.forTheForm();

        assertThat(regionsOf(companies, FRESH)).containsExactly("Mount Lebanon", "South");
        assertThat(regionsOf(companies, BY_HAND)).isEmpty();
        assertThat(HiringCompanies.REGISTRATION_REGIONS)
                .containsExactly("Beirut", "Mount Lebanon", "North", "South", "Bekaa");
    }

    @Test
    @DisplayName("a delivery company's application is recorded with its coverage kept to those five; anybody else's as sent")
    void coverage_is_kept_to_the_forms_regions_when_recorded() {
        Map<String, Object> sent = new HashMap<>();
        sent.put("fleetBand", "10 - 25 riders");
        sent.put("coverage", List.of("North", "Call 70 123 456", "Bekaa"));

        Map<String, Object> recorded = HiringCompanies.withRegisteredCoverage(Kind.CARRIER, sent);

        assertThat(recorded).containsEntry("coverage", List.of("North", "Bekaa"))
                .containsEntry("fleetBand", "10 - 25 riders");
        assertThat(sent.get("coverage")).isEqualTo(List.of("North", "Call 70 123 456", "Bekaa"));
        // Not a list at all reads as no region, as it does on the way out.
        assertThat(HiringCompanies.withRegisteredCoverage(Kind.CARRIER, Map.of("coverage", "Beirut")))
                .containsEntry("coverage", List.of());
        Map<String, Object> silent = Map.of("fleetBand", "1 - 9 riders");
        assertThat(HiringCompanies.withRegisteredCoverage(Kind.CARRIER, silent)).isSameAs(silent);
        Map<String, Object> rider = Map.of("coverage", List.of("Anything"));
        assertThat(HiringCompanies.withRegisteredCoverage(Kind.RIDER, rider)).isSameAs(rider);
        assertThat(HiringCompanies.withRegisteredCoverage(Kind.CARRIER, null)).isNull();
    }

    @Test
    @DisplayName("the open form's list is read once and served from memory for half a minute")
    void the_forms_list_is_remembered() {
        orderManagerLists();

        hiring.forTheForm();
        clock.advance(HiringCompanies.FORM_FRESH_FOR.minusSeconds(1));
        hiring.forTheForm();
        verify(platform, times(1)).hiringCompanies();

        clock.advance(Duration.ofSeconds(2));
        hiring.forTheForm();
        verify(platform, times(2)).hiringCompanies();
    }

    private static PlatformClient.CompaniesUnavailableException down() {
        return new PlatformClient.CompaniesUnavailableException("try again", null);
    }

    private static List<PlatformClient.HiringCompany> onlySwift() {
        return List.of(new PlatformClient.HiringCompany(SWIFT, "Swift Couriers", List.of("Hamra")));
    }

    @Test
    @DisplayName("while Order Manager cannot answer, the form is served the last list read, and asked again only after a few seconds")
    void an_outage_serves_the_last_list() {
        when(platform.hiringCompanies())
                .thenReturn(onlySwift())
                .thenThrow(down())
                .thenReturn(List.of(new PlatformClient.HiringCompany(FRESH, "Fresh Fleet",
                        List.of("Hamra"))));
        hiring.forTheForm();

        clock.advance(HiringCompanies.FORM_FRESH_FOR.plusSeconds(1));
        assertThat(hiring.forTheForm()).extracting(HiringCompanies.Company::name)
                .containsExactly("Swift Couriers");
        verify(platform, times(2)).hiringCompanies();

        // The failure is remembered: nobody waits on Order Manager again for a few seconds.
        clock.advance(HiringCompanies.FORM_FAILURE_REMEMBERED_FOR.minusSeconds(1));
        assertThat(hiring.forTheForm()).extracting(HiringCompanies.Company::name)
                .containsExactly("Swift Couriers");
        verify(platform, times(2)).hiringCompanies();

        clock.advance(Duration.ofSeconds(2));
        assertThat(hiring.forTheForm()).extracting(HiringCompanies.Company::name)
                .containsExactly("Fresh Fleet");
        verify(platform, times(3)).hiringCompanies();
    }

    @Test
    @DisplayName("with no list ever read, a failure is \"try again\" — and for a few seconds it is said at once, without asking again")
    void a_failure_with_nothing_to_offer_is_remembered() {
        when(platform.hiringCompanies()).thenThrow(down()).thenReturn(onlySwift());

        assertThatThrownBy(() -> hiring.forTheForm())
                .isInstanceOf(PlatformClient.CompaniesUnavailableException.class);
        clock.advance(HiringCompanies.FORM_FAILURE_REMEMBERED_FOR.minusSeconds(1));
        assertThatThrownBy(() -> hiring.forTheForm())
                .isInstanceOf(PlatformClient.CompaniesUnavailableException.class);
        verify(platform, times(1)).hiringCompanies();

        clock.advance(Duration.ofSeconds(2));
        assertThat(hiring.forTheForm()).extracting(HiringCompanies.Company::name)
                .containsExactly("Swift Couriers");
        verify(platform, times(2)).hiringCompanies();
    }

    /**
     * Order Manager is slow rather than refusing: each read waits out the bounded wait. Only one
     * request may be doing that; everybody else is answered at once.
     */
    @Test
    @DisplayName("only one request at a time waits on Order Manager; the others are served the last list at once, or \"try again\" when there is none")
    void only_one_request_waits_on_order_manager() throws Exception {
        ExecutorService elsewhere = Executors.newSingleThreadExecutor();
        try {
            // Nothing read yet: while the first read is out, another caller is told to try again.
            CountDownLatch asked = new CountDownLatch(1);
            CountDownLatch answer = new CountDownLatch(1);
            doAnswer(slowly(asked, answer, onlySwift())).when(platform).hiringCompanies();
            Future<List<HiringCompanies.Company>> first = elsewhere.submit(hiring::forTheForm);
            assertThat(asked.await(5, TimeUnit.SECONDS)).isTrue();
            assertThatThrownBy(() -> hiring.forTheForm())
                    .isInstanceOf(PlatformClient.CompaniesUnavailableException.class);
            answer.countDown();
            assertThat(first.get(5, TimeUnit.SECONDS)).extracting(HiringCompanies.Company::name)
                    .containsExactly("Swift Couriers");

            // A list is on hand now: while the next read is out, a caller gets it without waiting.
            clock.advance(HiringCompanies.FORM_FRESH_FOR.plusSeconds(1));
            CountDownLatch askedAgain = new CountDownLatch(1);
            CountDownLatch answerAgain = new CountDownLatch(1);
            doAnswer(slowly(askedAgain, answerAgain, List.of(new PlatformClient.HiringCompany(FRESH,
                    "Fresh Fleet", List.of("Hamra"))))).when(platform).hiringCompanies();
            Future<List<HiringCompanies.Company>> second = elsewhere.submit(hiring::forTheForm);
            assertThat(askedAgain.await(5, TimeUnit.SECONDS)).isTrue();
            assertThat(hiring.forTheForm()).extracting(HiringCompanies.Company::name)
                    .containsExactly("Swift Couriers");
            answerAgain.countDown();
            assertThat(second.get(5, TimeUnit.SECONDS)).extracting(HiringCompanies.Company::name)
                    .containsExactly("Fresh Fleet");
            verify(platform, times(2)).hiringCompanies();
        } finally {
            elsewhere.shutdownNow();
        }
    }

    /** Order Manager answering only once the test says so: says it was asked, then waits. */
    private static Answer<List<PlatformClient.HiringCompany>> slowly(CountDownLatch asked,
            CountDownLatch answer, List<PlatformClient.HiringCompany> companies) {
        return invocation -> {
            asked.countDown();
            if (!answer.await(5, TimeUnit.SECONDS)) {
                throw new AssertionError("the test never let Order Manager answer");
            }
            return companies;
        };
    }

    @Test
    @DisplayName("judging an application reads afresh, finds the one company with its region, and nothing for one not hiring")
    void judging_is_never_from_memory() {
        orderManagerLists();
        registrationsHold(registered(FRESH, List.of("Bekaa"), Instant.parse("2026-08-01T09:00:00Z")));
        hiring.forTheForm();

        assertThat(hiring.find(FRESH)).get().extracting(HiringCompanies.Company::regions)
                .isEqualTo(List.of("Bekaa"));
        assertThat(hiring.find(SWIFT)).get().extracting(HiringCompanies.Company::regions)
                .isEqualTo(List.of("Achrafieh", "Hamra"));
        assertThat(hiring.find(UUID.randomUUID())).isEmpty();
        verify(platform, times(4)).hiringCompanies();
    }

    /**
     * The derived query is only parsed when the application starts — a mocked suite never would — so
     * its property names are checked against the entity here, the way Spring Data will at boot.
     */
    @Test
    @DisplayName("the applications query names real properties of an application")
    void the_query_names_real_properties() {
        PartTree query = new PartTree("findByKindAndProvisionedEntityIdIn", OnboardingApplication.class);

        assertThat(query.getParts()).extracting(part -> part.getProperty().toDotPath())
                .containsExactly("kind", "provisionedEntityId");
    }

    /** A clock the test moves by hand. */
    private static final class MovableClock extends Clock {

        private Instant now = Instant.parse("2026-09-19T10:00:00Z");

        void advance(Duration by) {
            now = now.plus(by);
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }
}
