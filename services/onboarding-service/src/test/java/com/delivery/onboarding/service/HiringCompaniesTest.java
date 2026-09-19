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

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
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
 * every company has zones; the open form's list from memory for half a minute; judging an application
 * never from memory.
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

    @Test
    @DisplayName("a failed read is not remembered: the next request asks Order Manager again")
    void a_failure_is_not_remembered() {
        when(platform.hiringCompanies())
                .thenThrow(new PlatformClient.CompaniesUnavailableException("try again", null))
                .thenReturn(List.of(new PlatformClient.HiringCompany(SWIFT, "Swift Couriers",
                        List.of("Hamra"))));

        assertThatThrownBy(() -> hiring.forTheForm())
                .isInstanceOf(PlatformClient.CompaniesUnavailableException.class);
        assertThat(hiring.forTheForm()).extracting(HiringCompanies.Company::name)
                .containsExactly("Swift Couriers");
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
