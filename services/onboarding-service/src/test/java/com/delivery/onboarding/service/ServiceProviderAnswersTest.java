package com.delivery.onboarding.service;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.camunda.bpm.engine.RuntimeService;
import org.camunda.bpm.engine.TaskService;
import org.camunda.bpm.engine.runtime.ProcessInstance;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.client.PlatformClient.ServiceArea;
import com.delivery.onboarding.domain.AutoApprovalAuditRepository;
import com.delivery.onboarding.domain.AutoApprovalDecisionRepository;
import com.delivery.onboarding.domain.CarrierRegistrationRepository;
import com.delivery.onboarding.domain.ContactVerification.Channel;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;
import com.delivery.onboarding.service.ServiceProviderAnswers.Checked;
import com.delivery.onboarding.service.ServiceProviderAnswers.ServiceAnswerException;
import com.delivery.onboarding.service.ServiceProviderAnswers.Summary;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * An application to offer services, as it is judged — and when.
 *
 * <p>Two properties matter more than the individual refusals. A category is accepted exactly when
 * Product Service says it is open — there is no second list here that could let Cleaning through
 * while Product Service would refuse to open the shop. And nothing about any other application
 * changes: a shop, a rider or a delivery company is recorded as before without Product Service being
 * asked anything.
 *
 * <p>The last groups pin the costs. The signup form's lists are served from memory for half a minute,
 * because anybody may ask for them, while the judgement never is. And the judgement is made before
 * the intake's transaction, never inside it, with a caller who has no valid proof refused before
 * Product Service hears of them — pinned through the open front door and by the shape of the classes.
 */
@DisplayName("a services provider's answers")
class ServiceProviderAnswersTest {

    private static final UUID MAR_MIKHAEL = UUID.fromString("5b0c2f5e-8f7a-4d61-9a55-0d1f7b1f2a11");
    private static final UUID HAMRA = UUID.fromString("0f6f0b1e-3c1d-4a7e-8c8b-2f5d6e7a9b10");

    private PlatformClient platform;
    private ServiceProviderAnswers answers;

    @BeforeEach
    void setUp() {
        platform = mock(PlatformClient.class);
        // The launch set: Cleaning, Beauty and Tutoring exist in the taxonomy but are closed.
        when(platform.openServiceCategories())
                .thenReturn(List.of("PRINTING", "TAILORING", "REPAIRS", "PHOTOGRAPHY"));
        when(platform.serviceAreas()).thenReturn(List.of(
                new ServiceArea(MAR_MIKHAEL, "Mar Mikhael"), new ServiceArea(HAMRA, "Hamra")));
        answers = new ServiceProviderAnswers(platform,
                new HiringCompanies(platform, mock(CarrierRegistrationRepository.class)));
    }

    private static Map<String, Object> services(Object category, Object area) {
        Map<String, Object> details = new HashMap<>();
        details.put("businessType", "SERVICES");
        if (category != null) {
            details.put("serviceCategory", category);
        }
        if (area != null) {
            details.put("area", area);
        }
        return details;
    }

    private static Map<String, Object> area(UUID zoneId, String label) {
        return Map.of("zoneId", zoneId.toString(), "label", label);
    }

    /** The code a refusal carries — what the app translates. Fails when there is no refusal. */
    private static String codeOf(Runnable call) {
        try {
            call.run();
        } catch (ServiceAnswerException e) {
            return e.code();
        }
        throw new AssertionError("expected a services refusal carrying a code");
    }

    /** A clock the test moves by hand. */
    private static final class MovableClock extends Clock {

        private Instant now = Instant.parse("2026-09-14T10:00:00Z");

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

    @Nested
    @DisplayName("on any other application")
    class OtherApplications {

        @Test
        @DisplayName("passes the details through untouched, and never asks Product Service")
        void other_details_pass_through_untouched() {
            Map<String, Object> bakery = Map.of("businessType", "BAKERY");
            Map<String, Object> rider = Map.of("vehicleType", "MOTORCYCLE");

            assertThat(answers.checked(Kind.MERCHANT, bakery, null).details()).isSameAs(bakery);
            assertThat(answers.checked(Kind.RIDER, rider, null).details()).isSameAs(rider);
            assertThat(answers.checked(Kind.CARRIER, null, null).details()).isNull();
            verifyNoInteractions(platform);
        }

        /**
         * A delivery company's coverage is what riders are shown as its region, on the open hiring
         * list and on their own applications, and the form that writes it is open to anybody.
         */
        @Test
        @DisplayName("keeps a delivery company's coverage to the five regions its form offers, and the rest of its answers as sent")
        void a_companys_coverage_is_kept_to_the_forms_regions() {
            Map<String, Object> sent = new LinkedHashMap<>();
            sent.put("companyType", "Registered LLC");
            sent.put("coverage", new ArrayList<>(Arrays.asList(
                    "Beirut", "Cash jobs daily, call 70 123 456", " North ", "beirut", "Achrafieh", 7,
                    null, "Bekaa")));
            sent.put("fleetBand", "10 - 25 riders");

            Map<String, Object> recorded = answers.checked(Kind.CARRIER, sent, null).details();

            assertThat(recorded.get("coverage")).isEqualTo(List.of("Beirut", "North", "Bekaa"));
            assertThat(recorded)
                    .containsEntry("companyType", "Registered LLC")
                    .containsEntry("fleetBand", "10 - 25 riders");
            // What the wizard itself sends is recorded exactly as it came.
            Map<String, Object> fromTheWizard = Map.of("coverage", List.of("Beirut", "Mount Lebanon"));
            assertThat(answers.checked(Kind.CARRIER, fromTheWizard, null).details().get("coverage"))
                    .isEqualTo(List.of("Beirut", "Mount Lebanon"));
            // Nobody else's coverage is anybody's region, so nobody else's is touched.
            Map<String, Object> merchant = Map.of("coverage", List.of("Anything at all"));
            assertThat(answers.checked(Kind.MERCHANT, merchant, null).details()).isSameAs(merchant);
            verifyNoInteractions(platform);
        }
    }

    @Nested
    @DisplayName("refuses")
    class Refusals {

        @Test
        @DisplayName("an application to offer services that is not a shop's")
        void only_a_shop_offers_services() {
            assertThat(codeOf(() -> answers.checked(Kind.RIDER,
                    services("PRINTING", area(HAMRA, "Hamra")), null)))
                    .isEqualTo(ServiceAnswerException.NOT_A_SHOP);
            verifyNoInteractions(platform);
        }

        @Test
        @DisplayName("a missing category, before Product Service is asked anything")
        void a_category_is_required() {
            assertThat(codeOf(() -> answers.checked(Kind.MERCHANT,
                    services(null, area(HAMRA, "Hamra")), null)))
                    .isEqualTo(ServiceAnswerException.CATEGORY_MISSING);
            assertThat(codeOf(() -> answers.checked(Kind.MERCHANT,
                    services("   ", area(HAMRA, "Hamra")), null)))
                    .isEqualTo(ServiceAnswerException.CATEGORY_MISSING);
            verifyNoInteractions(platform);
        }

        @Test
        @DisplayName("a missing or malformed area, before Product Service is asked anything")
        void an_area_is_required() {
            assertThat(codeOf(() -> answers.checked(Kind.MERCHANT, services("PRINTING", null), null)))
                    .isEqualTo(ServiceAnswerException.AREA_MISSING);
            assertThat(codeOf(() -> answers.checked(Kind.MERCHANT,
                    services("PRINTING", "Mar Mikhael, Beirut"), null)))
                    .isEqualTo(ServiceAnswerException.AREA_MISSING);
            assertThat(codeOf(() -> answers.checked(Kind.MERCHANT,
                    services("PRINTING", Map.of("zoneId", "not-a-zone", "label", "Hamra")), null)))
                    .isEqualTo(ServiceAnswerException.AREA_MISSING);
            verifyNoInteractions(platform);
        }

        @Test
        @DisplayName("a category Product Service has closed")
        void a_closed_category() {
            assertThat(codeOf(() -> answers.checked(Kind.MERCHANT,
                    services("CLEANING", area(HAMRA, "Hamra")), null)))
                    .isEqualTo(ServiceAnswerException.CATEGORY_CLOSED);
            // Refused on the category; the zones are not worth reading for an application that is
            // already refused.
            verify(platform, never()).serviceAreas();
        }

        @Test
        @DisplayName("something that is not a category at all, the same way as a closed one")
        void not_a_category() {
            assertThat(codeOf(() -> answers.checked(Kind.MERCHANT,
                    services("KNITTING", area(HAMRA, "Hamra")), null)))
                    .isEqualTo(ServiceAnswerException.CATEGORY_CLOSED);
        }

        @Test
        @DisplayName("an area that is not a live delivery zone")
        void an_unknown_area() {
            UUID retired = UUID.fromString("9d9d9d9d-1111-4222-8333-444455556666");

            assertThat(codeOf(() -> answers.checked(Kind.MERCHANT,
                    services("PRINTING", area(retired, "Gemmayze")), null)))
                    .isEqualTo(ServiceAnswerException.AREA_UNKNOWN);
        }
    }

    @Nested
    @DisplayName("accepts an open category in a live area")
    class Accepted {

        @Test
        @DisplayName("and records it in canonical form, with the area named as its zone is named")
        void records_canonical_answers() {
            Map<String, Object> sent = services("printing", area(MAR_MIKHAEL, "mar mikhael beirut!!"));
            sent.put("businessType", "services");
            sent.put("notesForReviewer", "We print on fabric too");

            Map<String, Object> recorded = answers.checked(Kind.MERCHANT, sent, null).details();

            assertThat(recorded)
                    .containsEntry("businessType", "SERVICES")
                    .containsEntry("serviceCategory", "PRINTING")
                    .containsEntry("area", Map.of("zoneId", MAR_MIKHAEL.toString(),
                            "label", "Mar Mikhael"))
                    // Everything else the wizard sent is kept as it came.
                    .containsEntry("notesForReviewer", "We print on fabric too");
        }

        @Test
        @DisplayName("but never a companyRegions it sent: only a company rider's check writes that")
        void a_region_it_claimed_is_dropped() {
            Map<String, Object> sent = services("PRINTING", area(HAMRA, "Hamra"));
            sent.put("companyRegions", List.of("Anywhere you like"));

            Map<String, Object> recorded = answers.checked(Kind.MERCHANT, sent, null).details();

            assertThat(recorded).doesNotContainKey("companyRegions")
                    .containsEntry("serviceCategory", "PRINTING");
        }

        @Test
        @DisplayName("exactly when Product Service opens it — a category opened there is accepted here")
        void follows_product_service() {
            when(platform.openServiceCategories()).thenReturn(List.of("PRINTING", "CLEANING"));

            assertThat(answers.checked(Kind.MERCHANT,
                    services("CLEANING", area(HAMRA, "Hamra")), null).details())
                    .containsEntry("serviceCategory", "CLEANING");
        }
    }

    @Test
    @DisplayName("a Product Service outage is not a refusal: nothing was judged, so the applicant retries")
    void an_outage_is_not_a_refusal() {
        when(platform.openServiceCategories()).thenThrow(
                new PlatformClient.CatalogUnavailableException("try again", null));

        assertThatThrownBy(() -> answers.checked(Kind.MERCHANT,
                services("PRINTING", area(HAMRA, "Hamra")), null))
                .isInstanceOf(PlatformClient.CatalogUnavailableException.class)
                .isNotInstanceOf(ServiceAnswerException.class);
    }

    @Nested
    @DisplayName("on the applicant's receipt")
    class OnTheReceipt {

        @Test
        @DisplayName("shows the category and area of a services application")
        void shows_the_services_answers() {
            Map<String, Object> recorded = Map.of(
                    "businessType", "SERVICES",
                    "serviceCategory", "PRINTING",
                    "area", Map.of("zoneId", MAR_MIKHAEL.toString(), "label", "Mar Mikhael"),
                    "payout", Map.of("iban", "LB62099900000001001901229114"));

            assertThat(ServiceProviderAnswers.summaryOf(recorded))
                    .isEqualTo(new Summary("PRINTING", MAR_MIKHAEL.toString(), "Mar Mikhael"));
        }

        @Test
        @DisplayName("shows nothing for any other application")
        void nothing_for_anything_else() {
            assertThat(ServiceProviderAnswers.summaryOf(Map.of("businessType", "BAKERY"))).isNull();
            assertThat(ServiceProviderAnswers.summaryOf(null)).isNull();
        }
    }

    /**
     * {@code GET /service-options} is open to anybody, and each answer was two reads of Product
     * Service. So the lists are kept for half a minute — while an application is always judged
     * against what Product Service says at that moment.
     */
    @Nested
    @DisplayName("the signup form's lists")
    class TheFormsLists {

        private MovableClock clock;
        private ServiceProviderAnswers remembering;

        @BeforeEach
        void setUp() {
            clock = new MovableClock();
            remembering = new ServiceProviderAnswers(platform,
                    new HiringCompanies(platform, mock(CarrierRegistrationRepository.class)), clock);
        }

        @Test
        @DisplayName("are read once and served from memory for half a minute, however many ask")
        void are_served_from_memory() {
            ServiceProviderAnswers.Options first = remembering.options();
            clock.advance(ServiceProviderAnswers.OPTIONS_FRESH_FOR.minusSeconds(1));
            ServiceProviderAnswers.Options later = remembering.options();
            remembering.options();

            assertThat(first.categories())
                    .containsExactly("PRINTING", "TAILORING", "REPAIRS", "PHOTOGRAPHY");
            assertThat(later).isEqualTo(first);
            verify(platform, times(1)).openServiceCategories();
            verify(platform, times(1)).serviceAreas();
        }

        @Test
        @DisplayName("are read again once the half minute is up, so an opened category reaches the form")
        void are_read_again_after_the_half_minute() {
            remembering.options();
            when(platform.openServiceCategories()).thenReturn(List.of("PRINTING", "CLEANING"));
            clock.advance(ServiceProviderAnswers.OPTIONS_FRESH_FOR);

            assertThat(remembering.options().categories()).containsExactly("PRINTING", "CLEANING");
            verify(platform, times(2)).openServiceCategories();
        }

        @Test
        @DisplayName("are not remembered when Product Service cannot answer: the next request asks again")
        void an_outage_is_not_remembered() {
            when(platform.openServiceCategories())
                    .thenThrow(new PlatformClient.CatalogUnavailableException("try again", null))
                    .thenReturn(List.of("PRINTING"));

            assertThatThrownBy(remembering::options)
                    .isInstanceOf(PlatformClient.CatalogUnavailableException.class);
            assertThat(remembering.options().categories()).containsExactly("PRINTING");
            verify(platform, times(2)).openServiceCategories();
        }

        @Test
        @DisplayName("never stand in for the judgement: an application is checked against what is open now")
        void the_judgement_is_never_remembered() {
            remembering.options();
            // Printing closes while the lists are still being served from memory.
            when(platform.openServiceCategories()).thenReturn(List.of("TAILORING"));

            assertThat(remembering.options().categories()).contains("PRINTING");
            assertThat(codeOf(() -> remembering.checked(Kind.MERCHANT,
                    services("PRINTING", area(HAMRA, "Hamra")), null)))
                    .isEqualTo(ServiceAnswerException.CATEGORY_CLOSED);
            verify(platform, times(2)).openServiceCategories();
        }
    }

    /**
     * The intake's transaction holds a pooled connection from the moment it begins — twelve, shared
     * with the workflow engine — and the open front door takes applications from anybody. So the check
     * is made before the intake is entered, and a caller with no valid proof is refused before
     * Product Service is asked. Pinned through the open door with a real check and a stand-in intake
     * (the signed-in door is pinned the same way in AccountApplicationServiceTest), and by the shape
     * of the classes, because a mocked suite cannot watch a transaction boundary.
     */
    @Nested
    @DisplayName("is made before the intake's transaction, never inside it")
    class BeforeTheIntake {

        private ApplicationIntake intake;
        private VerificationService verifications;
        private OnboardingService onboarding;

        @BeforeEach
        void setUp() {
            intake = mock(ApplicationIntake.class);
            verifications = mock(VerificationService.class);
            when(intake.record(any(), any(), any(), any(), any(), any(), any(), any(), any(), any()))
                    .thenAnswer(call -> new OnboardingApplication(call.getArgument(0),
                            call.getArgument(1), call.getArgument(2), call.getArgument(3),
                            Instant.now(), null, null, null,
                            call.<Checked>getArgument(8).details(), null));
            RuntimeService runtime = mock(RuntimeService.class);
            ProcessInstance started = mock(ProcessInstance.class);
            when(started.getId()).thenReturn("process-1");
            when(runtime.startProcessInstanceByKey(anyString(), anyString(), anyMap()))
                    .thenReturn(started);
            onboarding = new OnboardingService(mock(OnboardingApplicationRepository.class), intake,
                    verifications, answers, runtime, mock(TaskService.class),
                    mock(KeycloakAdminClient.class), mock(ApplicantDocumentService.class),
                    new AutoApprovalPolicy(false, false, false,
                            mock(AutoApprovalDecisionRepository.class),
                            mock(AutoApprovalAuditRepository.class)));
        }

        /** The open form's services application, with the email proof "email-proof". */
        private OnboardingApplication applyAsPrintShop(String category, String phone,
                                                       String phoneProof) {
            return onboarding.submit(Kind.MERCHANT, "Al Fakhry Press", "Sam Salem",
                    "sam@example.test", "email-proof", phone, phoneProof, null,
                    services(category, area(HAMRA, "Hamra")), null);
        }

        private void emailProved() {
            when(verifications.isVerified("email-proof", Channel.EMAIL, "sam@example.test"))
                    .thenReturn(true);
        }

        @Test
        @DisplayName("a caller with no valid proof is refused without a call to Product Service, and spends nothing")
        void no_valid_proof_asks_nobody() {
            // isVerified answers false for anything not stubbed: a made-up token.
            assertThatThrownBy(() -> applyAsPrintShop("PRINTING", null, null))
                    .isInstanceOf(VerificationService.VerificationException.class);

            verifyNoInteractions(platform, intake);
            verify(verifications, never()).consume(any(), any(), any());
        }

        @Test
        @DisplayName("an unproved phone number is refused the same way, before Product Service")
        void an_unproved_phone_asks_nobody() {
            emailProved();

            assertThatThrownBy(() -> applyAsPrintShop("PRINTING", "+96171234567", "made-up"))
                    .isInstanceOf(VerificationService.VerificationException.class);

            verifyNoInteractions(platform, intake);
        }

        @Test
        @DisplayName("a blank token is refused without even a lookup")
        void a_blank_token_is_not_looked_up() {
            assertThatThrownBy(() -> onboarding.submit(Kind.MERCHANT, "Al Fakhry Press",
                    "Sam Salem", "sam@example.test", " ", null, null, null,
                    services("PRINTING", area(HAMRA, "Hamra")), null))
                    .isInstanceOf(VerificationService.VerificationException.class);

            verifyNoInteractions(verifications, platform, intake);
        }

        @Test
        @DisplayName("a closed category is refused before the intake is entered, so no proof is spent")
        void a_closed_category_spends_nothing() {
            emailProved();

            assertThat(codeOf(() -> applyAsPrintShop("BEAUTY", null, null)))
                    .isEqualTo(ServiceAnswerException.CATEGORY_CLOSED);

            verifyNoInteractions(intake);
            verify(verifications, never()).consume(any(), any(), any());
        }

        @Test
        @DisplayName("the proof, then Product Service, then the intake — which records what the check made")
        void asked_before_the_intake() {
            emailProved();

            applyAsPrintShop("printing", null, null);

            InOrder order = inOrder(verifications, platform, intake);
            order.verify(verifications).isVerified("email-proof", Channel.EMAIL, "sam@example.test");
            order.verify(platform).openServiceCategories();
            order.verify(platform).serviceAreas();
            order.verify(intake).record(eq(Kind.MERCHANT), any(), any(), any(), eq("email-proof"),
                    any(), any(), any(),
                    argThat((Checked checked) ->
                            "PRINTING".equals(checked.details().get("serviceCategory"))
                                    && area(HAMRA, "Hamra").equals(checked.details().get("area"))),
                    any());
        }

        @Test
        @DisplayName("any other application goes straight to the intake: no early look at the proof, nobody asked")
        void other_applications_are_unchanged() {
            onboarding.submit(Kind.MERCHANT, "Sam's Bakery", "Sam Salem", "sam@example.test",
                    "email-proof", null, null, null, Map.of("businessType", "BAKERY"), null);

            verifyNoInteractions(verifications, platform);
            verify(intake).record(eq(Kind.MERCHANT), any(), any(), any(), eq("email-proof"), any(),
                    any(), any(),
                    argThat((Checked checked) ->
                            Map.of("businessType", "BAKERY").equals(checked.details())),
                    any());
        }

        /** A rider's open-form answers as an installed app still sends them: an area and a pin. */
        private Map<String, Object> riderAnswers() {
            return Map.of("vehicleType", "MOTORCYCLE", "preferredArea", "Hamra",
                    "workLatitude", 33.8959, "workLongitude", 35.4828);
        }

        @Test
        @DisplayName("a rider naming a company: the proof, then Order Manager, then the intake — which records the company's region, not the pin")
        void a_company_rider_is_judged_before_the_intake() {
            emailProved();
            UUID swift = UUID.randomUUID();
            when(platform.hiringCompanies()).thenReturn(List.of(
                    new PlatformClient.HiringCompany(swift, "Swift Couriers",
                            List.of("Achrafieh", "Hamra"))));

            onboarding.submit(Kind.RIDER, "Sam Salem", "Sam Salem", "sam@example.test",
                    "email-proof", null, null, null, riderAnswers(), swift);

            InOrder order = inOrder(verifications, platform, intake);
            order.verify(verifications).isVerified("email-proof", Channel.EMAIL, "sam@example.test");
            order.verify(platform).hiringCompanies();
            order.verify(intake).record(eq(Kind.RIDER), any(), any(), any(), eq("email-proof"),
                    any(), any(), any(),
                    argThat((Checked checked) ->
                            List.of("Achrafieh", "Hamra").equals(checked.details().get("companyRegions"))
                                    && "MOTORCYCLE".equals(checked.details().get("vehicleType"))
                                    && !checked.details().containsKey("preferredArea")
                                    && !checked.details().containsKey("workLatitude")
                                    && !checked.details().containsKey("workLongitude")),
                    eq(swift));
            // A rider is not a services application: Product Service is not asked about them.
            verify(platform, never()).openServiceCategories();
            verify(platform, never()).serviceAreas();
        }

        @Test
        @DisplayName("a rider naming a company with no valid proof is refused without a call to Order Manager")
        void a_company_rider_without_proof_asks_nobody() {
            assertThatThrownBy(() -> onboarding.submit(Kind.RIDER, "Sam Salem", "Sam Salem",
                    "sam@example.test", "made-up", null, null, null, riderAnswers(),
                    UUID.randomUUID()))
                    .isInstanceOf(VerificationService.VerificationException.class);

            verifyNoInteractions(platform, intake);
        }

        @Test
        @DisplayName("a company that is not hiring is refused by name on the open form too, and spends no proof")
        void a_company_not_hiring_spends_nothing() {
            emailProved();
            when(platform.hiringCompanies()).thenReturn(List.of());

            assertThatThrownBy(() -> onboarding.submit(Kind.RIDER, "Sam Salem", "Sam Salem",
                    "sam@example.test", "email-proof", null, null, null, riderAnswers(),
                    UUID.randomUUID()))
                    .isInstanceOfSatisfying(CompanyRiderAnswers.CompanyAnswerException.class,
                            refused -> assertThat(refused.code()).isEqualTo("company-not-hiring"));

            verifyNoInteractions(intake);
            verify(verifications, never()).consume(any(), any(), any());
        }

        @Test
        @DisplayName("a rider riding for YouDrop is not looked at early and keeps the area and pin they chose")
        void a_rider_for_youdrop_is_unchanged() {
            onboarding.submit(Kind.RIDER, "Sam Salem", "Sam Salem", "sam@example.test",
                    "email-proof", null, null, null, riderAnswers(), null);

            verifyNoInteractions(verifications, platform);
            verify(intake).record(eq(Kind.RIDER), any(), any(), any(), eq("email-proof"), any(),
                    any(), any(),
                    argThat((Checked checked) -> riderAnswers().equals(checked.details())),
                    any());
        }

        @Test
        @DisplayName("by shape: the intake cannot reach Product Service, and neither front door is transactional")
        void the_transaction_does_not_span_the_reads() throws NoSuchMethodException {
            // Nothing the intake is built from, or holds, can call Product Service...
            assertThat(Arrays.stream(ApplicationIntake.class.getDeclaredConstructors())
                    .flatMap(constructor -> Arrays.stream(constructor.getParameterTypes())))
                    .doesNotContain(ServiceProviderAnswers.class, PlatformClient.class);
            assertThat(Arrays.stream(ApplicationIntake.class.getDeclaredFields()).map(Field::getType))
                    .doesNotContain(ServiceProviderAnswers.class, PlatformClient.class);

            // ...its writes take only details that were checked before they began...
            Method record = ApplicationIntake.class.getMethod("record", Kind.class, String.class,
                    String.class, String.class, String.class, String.class, String.class,
                    String.class, Checked.class, UUID.class);
            Method recordForAccount = ApplicationIntake.class.getMethod("recordForAccount",
                    String.class, Kind.class, String.class, String.class, String.class,
                    Instant.class, String.class, String.class, String.class, Checked.class,
                    UUID.class);
            for (Method write : List.of(record, recordForAccount)) {
                assertThat(write.getAnnotation(Transactional.class).propagation())
                        .isEqualTo(Propagation.REQUIRES_NEW);
            }

            // ...and the doors that make the check hold no transaction while Product Service answers.
            Method submit = OnboardingService.class.getMethod("submit", Kind.class, String.class,
                    String.class, String.class, String.class, String.class, String.class,
                    String.class, Map.class, UUID.class);
            Method apply = AccountApplicationService.class.getMethod("apply",
                    AccountApplicationService.Caller.class, AccountApplicationService.Answers.class);
            for (Method door : List.of(submit, apply)) {
                assertThat(door.getAnnotation(Transactional.class)).as("%s", door).isNull();
                assertThat(door.getDeclaringClass().getAnnotation(Transactional.class))
                        .as("%s", door.getDeclaringClass()).isNull();
            }
        }
    }
}
