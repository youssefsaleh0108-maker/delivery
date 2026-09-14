package com.delivery.onboarding.api;

import java.io.IOException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.EnumerablePropertySource;
import org.springframework.core.env.PropertySource;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.MediaType;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.client.PlatformClient.ServiceArea;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.service.AccountApplicationService;
import com.delivery.onboarding.service.AccountApplicationService.Result;
import com.delivery.onboarding.service.ApplicantDocumentService;
import com.delivery.onboarding.service.CustomerSignUpService;
import com.delivery.onboarding.service.OnboardingService;
import com.delivery.onboarding.service.PartnerManagementService;
import com.delivery.onboarding.service.PayoutDetailsService;
import com.delivery.onboarding.service.ServiceProviderAnswers;
import com.delivery.onboarding.service.ServiceProviderAnswers.ServiceAnswerException;
import com.delivery.onboarding.service.VerificationService;

import com.fasterxml.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.nullValue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * What the services signup form reads and what its two front doors answer.
 *
 * <p>The options are the one new endpoint, and the one new entry on the permit-all list, so both are
 * pinned: the form works with no account, and nothing that was keyed on the caller became open with
 * it. The rest pins what the app relies on at either front door — a refused services answer is a 422
 * the app can translate by its code, an outage in Product Service is a 503 it can offer a retry for,
 * and the receipt carries the category and area the provider's app opens the shop from, with nothing
 * else from the details.
 */
@DisplayName("the services signup endpoints")
class ServiceSignupAccessTest {

    private static final ObjectMapper JSON = new ObjectMapper();

    private static final UUID MAR_MIKHAEL = UUID.fromString("5b0c2f5e-8f7a-4d61-9a55-0d1f7b1f2a11");

    private static final Map<String, Object> PRINT_SHOP = Map.of(
            "businessType", "SERVICES",
            "serviceCategory", "PRINTING",
            "area", Map.of("zoneId", MAR_MIKHAEL.toString(), "label", "Mar Mikhael"),
            "payout", Map.of("accountHolder", "Sam Salem", "iban", "LB62099900000001001901229114"));

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static OnboardingApplication application(Map<String, Object> details) {
        return new OnboardingApplication(Kind.MERCHANT, "Al Fakhry Press", "Sam Salem",
                "sam@example.test", Instant.now(), null, null, null, details, null);
    }

    private static String shopBody(Map<String, Object> extra) throws IOException {
        Map<String, Object> body = new HashMap<>(Map.of(
                "kind", "MERCHANT",
                "businessName", "Al Fakhry Press",
                "contactName", "Sam Salem",
                "details", Map.of("businessType", "SERVICES", "serviceCategory", "CLEANING")));
        body.putAll(extra);
        return JSON.writeValueAsString(body);
    }

    @Nested
    @DisplayName("GET /api/onboarding/service-options")
    class TheOptions {

        private ServiceProviderAnswers answers;
        private MockMvc mvc;

        @BeforeEach
        void setUp() {
            answers = mock(ServiceProviderAnswers.class);
            mvc = MockMvcBuilders.standaloneSetup(new ServiceSignupController(answers)).build();
        }

        @Test
        @DisplayName("lists the open categories and the areas, by zone id and name")
        void lists_categories_and_areas() throws Exception {
            when(answers.options()).thenReturn(new ServiceProviderAnswers.Options(
                    List.of("PRINTING", "REPAIRS"),
                    List.of(new ServiceArea(MAR_MIKHAEL, "Mar Mikhael"))));

            mvc.perform(get("/api/onboarding/service-options"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.categories[0]").value("PRINTING"))
                    .andExpect(jsonPath("$.categories[1]").value("REPAIRS"))
                    .andExpect(jsonPath("$.categories.length()").value(2))
                    .andExpect(jsonPath("$.areas[0].zoneId").value(MAR_MIKHAEL.toString()))
                    .andExpect(jsonPath("$.areas[0].name").value("Mar Mikhael"));
        }

        @Test
        @DisplayName("is a 503 with its code when Product Service cannot answer")
        void an_outage_is_503() throws Exception {
            when(answers.options()).thenThrow(
                    new PlatformClient.CatalogUnavailableException("Please try again", null));

            mvc.perform(get("/api/onboarding/service-options"))
                    .andExpect(status().isServiceUnavailable())
                    .andExpect(jsonPath("$.code").value("service-catalog-unavailable"));
        }

        @Test
        @DisplayName("is open to somebody with no account, and opens nothing keyed on the caller")
        void is_on_permit_all_and_mine_is_not() throws IOException {
            List<String> open = permitAll();

            assertThat(open).contains("/api/onboarding/service-options");
            assertThat(open).doesNotContain("/api/onboarding/applications/mine",
                    "/api/onboarding/**", "/api/onboarding/*");
        }

        private List<String> permitAll() throws IOException {
            List<PropertySource<?>> sources = new YamlPropertySourceLoader()
                    .load("application", new ClassPathResource("application.yml"));
            List<String> paths = new ArrayList<>();
            for (PropertySource<?> source : sources) {
                if (!(source instanceof EnumerablePropertySource<?> listed)) {
                    continue;
                }
                for (String name : listed.getPropertyNames()) {
                    if (name.startsWith("delivery.security.permit-all[")) {
                        paths.add(String.valueOf(listed.getProperty(name)));
                    }
                }
            }
            assertThat(paths).as("the permit-all list was read").isNotEmpty();
            return paths;
        }
    }

    @Nested
    @DisplayName("POST /api/onboarding/applications/mine")
    class TheSignedInFrontDoor {

        private AccountApplicationService accounts;
        private MockMvc mvc;

        @BeforeEach
        void setUp() {
            accounts = mock(AccountApplicationService.class);
            mvc = MockMvcBuilders.standaloneSetup(new AccountOnboardingController(accounts)).build();
            SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(
                    Jwt.withTokenValue("token").header("alg", "none").subject("keycloak-sub-sam")
                            .claim("email", "sam@gmail.example").claim("email_verified", true)
                            .build(),
                    List.of()));
        }

        @Test
        @DisplayName("answers a closed category with 422 and its code")
        void a_closed_category_is_422_with_its_code() throws Exception {
            when(accounts.apply(any(), any())).thenThrow(new ServiceAnswerException(
                    ServiceAnswerException.CATEGORY_CLOSED,
                    "YouDrop is not taking applications for that service yet"));

            mvc.perform(post("/api/onboarding/applications/mine")
                            .contentType(MediaType.APPLICATION_JSON).content(shopBody(Map.of())))
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.code").value("service-category-closed"));
        }

        @Test
        @DisplayName("answers a Product Service outage with 503 and its code")
        void an_outage_is_503() throws Exception {
            when(accounts.apply(any(), any())).thenThrow(
                    new PlatformClient.CatalogUnavailableException("Please try again", null));

            mvc.perform(post("/api/onboarding/applications/mine")
                            .contentType(MediaType.APPLICATION_JSON).content(shopBody(Map.of())))
                    .andExpect(status().isServiceUnavailable())
                    .andExpect(jsonPath("$.code").value("service-catalog-unavailable"));
        }

        @Test
        @DisplayName("hands back a receipt carrying the category and area, and nothing else from details")
        void the_receipt_carries_the_services_answers() throws Exception {
            when(accounts.apply(any(), any()))
                    .thenReturn(new Result(application(PRINT_SHOP), true));

            mvc.perform(post("/api/onboarding/applications/mine")
                            .contentType(MediaType.APPLICATION_JSON).content(shopBody(Map.of())))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.service.category").value("PRINTING"))
                    .andExpect(jsonPath("$.service.zoneId").value(MAR_MIKHAEL.toString()))
                    .andExpect(jsonPath("$.service.area").value("Mar Mikhael"))
                    // The bank details in the same document never ride along.
                    .andExpect(jsonPath("$.details").doesNotExist())
                    .andExpect(jsonPath("$.service.iban").doesNotExist());
        }

        @Test
        @DisplayName("carries no services block for any other application")
        void no_block_for_a_shop() throws Exception {
            when(accounts.apply(any(), any())).thenReturn(
                    new Result(application(Map.of("businessType", "BAKERY")), true));

            mvc.perform(post("/api/onboarding/applications/mine")
                            .contentType(MediaType.APPLICATION_JSON).content(shopBody(Map.of())))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.service").value(nullValue()));
        }
    }

    @Nested
    @DisplayName("POST /api/onboarding/applications, the open form")
    class TheOpenFrontDoor {

        private OnboardingService onboarding;
        private MockMvc mvc;

        @BeforeEach
        void setUp() {
            onboarding = mock(OnboardingService.class);
            mvc = MockMvcBuilders.standaloneSetup(new OnboardingController(
                    onboarding, mock(VerificationService.class), mock(PlatformClient.class),
                    mock(CustomerSignUpService.class), mock(ApplicantDocumentService.class),
                    mock(PayoutDetailsService.class), mock(PartnerManagementService.class)))
                    .build();
        }

        private String openBody() throws IOException {
            return shopBody(Map.of(
                    "contactEmail", "sam@example.test",
                    "emailVerificationToken", "proof-token"));
        }

        @Test
        @DisplayName("answers a closed category with 422 and the same code as the signed-in door")
        void a_closed_category_is_422_with_its_code() throws Exception {
            when(onboarding.submit(any(), anyString(), anyString(), anyString(), anyString(),
                    any(), any(), any(), any(), any()))
                    .thenThrow(new ServiceAnswerException(ServiceAnswerException.CATEGORY_CLOSED,
                            "YouDrop is not taking applications for that service yet"));

            mvc.perform(post("/api/onboarding/applications")
                            .contentType(MediaType.APPLICATION_JSON).content(openBody()))
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.code").value("service-category-closed"));
        }

        @Test
        @DisplayName("still answers an uncoded refusal with its message alone")
        void an_uncoded_rule_is_unchanged() throws Exception {
            when(onboarding.submit(any(), anyString(), anyString(), anyString(), anyString(),
                    any(), any(), any(), any(), any()))
                    .thenThrow(new OnboardingService.ApplicationRuleException(
                            "You already have an application in progress for this business"));

            mvc.perform(post("/api/onboarding/applications")
                            .contentType(MediaType.APPLICATION_JSON).content(openBody()))
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.message").value(
                            "You already have an application in progress for this business"))
                    .andExpect(jsonPath("$.code").doesNotExist());
        }

        @Test
        @DisplayName("answers a Product Service outage with 503 and its code")
        void an_outage_is_503() throws Exception {
            when(onboarding.submit(any(), anyString(), anyString(), anyString(), anyString(),
                    any(), any(), any(), any(), any()))
                    .thenThrow(new PlatformClient.CatalogUnavailableException("Please try again",
                            null));

            mvc.perform(post("/api/onboarding/applications")
                            .contentType(MediaType.APPLICATION_JSON).content(openBody()))
                    .andExpect(status().isServiceUnavailable())
                    .andExpect(jsonPath("$.code").value("service-catalog-unavailable"));
        }

        @Test
        @DisplayName("shows the services answers on the status lookup by reference")
        void the_status_lookup_carries_the_services_answers() throws Exception {
            OnboardingApplication printShop = application(PRINT_SHOP);
            when(onboarding.byReference(printShop.getReference()))
                    .thenReturn(Optional.of(printShop));

            mvc.perform(get("/api/onboarding/applications/by-reference/"
                            + printShop.getReference()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.service.category").value("PRINTING"))
                    .andExpect(jsonPath("$.service.area").value("Mar Mikhael"));
        }
    }
}
