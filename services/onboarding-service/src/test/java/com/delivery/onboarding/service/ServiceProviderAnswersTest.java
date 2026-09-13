package com.delivery.onboarding.service;

import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.client.PlatformClient.ServiceArea;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;
import com.delivery.onboarding.service.ServiceProviderAnswers.ServiceAnswerException;
import com.delivery.onboarding.service.ServiceProviderAnswers.Summary;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * An application to offer services, as the intake judges it.
 *
 * <p>Two properties matter more than the individual refusals. A category is accepted exactly when
 * Product Service says it is open — there is no second list here that could let Cleaning through
 * while Product Service would refuse to open the shop. And nothing about any other application
 * changes: a shop, a rider or a delivery company is recorded as before without Product Service being
 * asked anything. The last group runs both front doors through a real {@link ApplicationIntake}, so
 * the check is pinned where it is enforced rather than only where it is written.
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
        answers = new ServiceProviderAnswers(platform);
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

    @Nested
    @DisplayName("on any other application")
    class OtherApplications {

        @Test
        @DisplayName("passes the details through untouched, and never asks Product Service")
        void other_details_pass_through_untouched() {
            Map<String, Object> bakery = Map.of("businessType", "BAKERY");
            Map<String, Object> rider = Map.of("vehicleType", "MOTORCYCLE");

            assertThat(answers.checked(Kind.MERCHANT, bakery)).isSameAs(bakery);
            assertThat(answers.checked(Kind.RIDER, rider)).isSameAs(rider);
            assertThat(answers.checked(Kind.CARRIER, null)).isNull();
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
                    services("PRINTING", area(HAMRA, "Hamra")))))
                    .isEqualTo(ServiceAnswerException.NOT_A_SHOP);
            verifyNoInteractions(platform);
        }

        @Test
        @DisplayName("a missing category, before Product Service is asked anything")
        void a_category_is_required() {
            assertThat(codeOf(() -> answers.checked(Kind.MERCHANT,
                    services(null, area(HAMRA, "Hamra")))))
                    .isEqualTo(ServiceAnswerException.CATEGORY_MISSING);
            assertThat(codeOf(() -> answers.checked(Kind.MERCHANT,
                    services("   ", area(HAMRA, "Hamra")))))
                    .isEqualTo(ServiceAnswerException.CATEGORY_MISSING);
            verifyNoInteractions(platform);
        }

        @Test
        @DisplayName("a missing or malformed area, before Product Service is asked anything")
        void an_area_is_required() {
            assertThat(codeOf(() -> answers.checked(Kind.MERCHANT, services("PRINTING", null))))
                    .isEqualTo(ServiceAnswerException.AREA_MISSING);
            assertThat(codeOf(() -> answers.checked(Kind.MERCHANT,
                    services("PRINTING", "Mar Mikhael, Beirut"))))
                    .isEqualTo(ServiceAnswerException.AREA_MISSING);
            assertThat(codeOf(() -> answers.checked(Kind.MERCHANT,
                    services("PRINTING", Map.of("zoneId", "not-a-zone", "label", "Hamra")))))
                    .isEqualTo(ServiceAnswerException.AREA_MISSING);
            verifyNoInteractions(platform);
        }

        @Test
        @DisplayName("a category Product Service has closed")
        void a_closed_category() {
            assertThat(codeOf(() -> answers.checked(Kind.MERCHANT,
                    services("CLEANING", area(HAMRA, "Hamra")))))
                    .isEqualTo(ServiceAnswerException.CATEGORY_CLOSED);
            // Refused on the category; the zones are not worth reading for an application that is
            // already refused.
            verify(platform, never()).serviceAreas();
        }

        @Test
        @DisplayName("something that is not a category at all, the same way as a closed one")
        void not_a_category() {
            assertThat(codeOf(() -> answers.checked(Kind.MERCHANT,
                    services("KNITTING", area(HAMRA, "Hamra")))))
                    .isEqualTo(ServiceAnswerException.CATEGORY_CLOSED);
        }

        @Test
        @DisplayName("an area that is not a live delivery zone")
        void an_unknown_area() {
            UUID retired = UUID.fromString("9d9d9d9d-1111-4222-8333-444455556666");

            assertThat(codeOf(() -> answers.checked(Kind.MERCHANT,
                    services("PRINTING", area(retired, "Gemmayze")))))
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

            Map<String, Object> recorded = answers.checked(Kind.MERCHANT, sent);

            assertThat(recorded)
                    .containsEntry("businessType", "SERVICES")
                    .containsEntry("serviceCategory", "PRINTING")
                    .containsEntry("area", Map.of("zoneId", MAR_MIKHAEL.toString(),
                            "label", "Mar Mikhael"))
                    // Everything else the wizard sent is kept as it came.
                    .containsEntry("notesForReviewer", "We print on fabric too");
        }

        @Test
        @DisplayName("exactly when Product Service opens it — a category opened there is accepted here")
        void follows_product_service() {
            when(platform.openServiceCategories()).thenReturn(List.of("PRINTING", "CLEANING"));

            assertThat(answers.checked(Kind.MERCHANT, services("CLEANING", area(HAMRA, "Hamra"))))
                    .containsEntry("serviceCategory", "CLEANING");
        }
    }

    @Test
    @DisplayName("a Product Service outage is not a refusal: nothing was judged, so the applicant retries")
    void an_outage_is_not_a_refusal() {
        when(platform.openServiceCategories()).thenThrow(
                new PlatformClient.CatalogUnavailableException("try again", null));

        assertThatThrownBy(() -> answers.checked(Kind.MERCHANT,
                services("PRINTING", area(HAMRA, "Hamra"))))
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

    @Nested
    @DisplayName("enforced by the intake, on both front doors")
    class ThroughTheIntake {

        private OnboardingApplicationRepository applications;
        private VerificationService verifications;
        private ApplicationIntake intake;

        @BeforeEach
        void setUp() {
            applications = mock(OnboardingApplicationRepository.class);
            verifications = mock(VerificationService.class);
            when(verifications.consume(any(), any(), any())).thenReturn(Instant.now());
            when(verifications.normalise(any(), any())).thenAnswer(call -> call.getArgument(1));
            when(applications.saveAndFlush(any(OnboardingApplication.class)))
                    .thenAnswer(call -> call.getArgument(0));
            intake = new ApplicationIntake(applications, verifications, answers);
        }

        @Test
        @DisplayName("the open form: a closed category is refused before a proof is spent or a row written")
        void open_form_refuses_before_spending_the_proof() {
            assertThat(codeOf(() -> intake.record(Kind.MERCHANT, "Al Fakhry Press", "Sam Salem",
                    "sam@example.test", "email-proof", null, null, null,
                    services("BEAUTY", area(HAMRA, "Hamra")), null)))
                    .isEqualTo(ServiceAnswerException.CATEGORY_CLOSED);

            verifyNoInteractions(verifications);
            verify(applications, never()).saveAndFlush(any());
        }

        @Test
        @DisplayName("the open form: an open category is recorded in canonical form")
        void open_form_records_the_checked_answers() {
            OnboardingApplication recorded = intake.record(Kind.MERCHANT, "Al Fakhry Press",
                    "Sam Salem", "sam@example.test", "email-proof", null, null, null,
                    services("printing", area(MAR_MIKHAEL, "anything")), null);

            assertThat(recorded.getDetails())
                    .containsEntry("serviceCategory", "PRINTING")
                    .containsEntry("area", Map.of("zoneId", MAR_MIKHAEL.toString(),
                            "label", "Mar Mikhael"));
        }

        @Test
        @DisplayName("a signed-in account: a closed category is refused before a row is written")
        void signed_in_refuses_before_writing() {
            assertThat(codeOf(() -> intake.recordForAccount("keycloak-sub-sam", Kind.MERCHANT,
                    "Al Fakhry Press", "Sam Salem", "sam@gmail.example", Instant.now(), null, null,
                    null, services("TUTORING", area(HAMRA, "Hamra")), null)))
                    .isEqualTo(ServiceAnswerException.CATEGORY_CLOSED);

            verify(applications, never()).saveAndFlush(any());
        }
    }
}
