package com.delivery.onboarding.api;

import java.time.Instant;
import java.util.Arrays;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.http.MediaType;
import org.springframework.security.authorization.method.AuthorizationManagerBeforeMethodInterceptor;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.web.BearerTokenAuthenticationEntryPoint;
import org.springframework.security.oauth2.server.resource.web.access.BearerTokenAccessDeniedHandler;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.web.access.ExceptionTranslationFilter;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.onboarding.domain.AutoApprovalSource;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.service.AutoApprovalPolicy;
import com.delivery.onboarding.service.AutoApprovalPolicy.KindDecision;
import com.delivery.onboarding.service.AutoApprovalPolicy.Settings;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.hamcrest.Matchers.nullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Only backoffice reaches the switch that decides who gets onto the platform unreviewed.
 *
 * <p>This is the one endpoint in the service whose ON position removes human review from every
 * later application, so the refusals matter at least as much as the happy path and are pinned
 * first: no token is 401, a partner's or a shopper's token is 403, and a body that does not say
 * what it means is 400 before anything is written.
 *
 * <p><strong>Why this suite builds more machinery than its neighbours.</strong> The other access
 * tests here drive a plain {@code standaloneSetup}, which never evaluates {@code @PreAuthorize} —
 * good enough where the check being pinned is an ownership check written in the controller's own
 * code, and worthless here, where the entire guard <em>is</em> the annotation. So the controller is
 * wrapped in the real Spring Security method interceptor and the real
 * {@link ExceptionTranslationFilter}, which is what turns the denial into the status code a client
 * sees: 401 when there is nobody to deny, 403 when there is somebody and they may not. A test that
 * asserted the annotation by reflection would pass just as happily with method security switched
 * off across the service.
 */
class AutoApprovalSettingsAccessTest {

    private static final String PATH = "/api/onboarding/admin/auto-approval";
    private static final String BACKOFFICE = "keycloak-sub-backoffice";

    private AutoApprovalPolicy policy;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        policy = mock(AutoApprovalPolicy.class);
        when(policy.settings()).thenReturn(allFromConfig());
        mvc = secured(new AutoApprovalSettingsController(policy));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    /**
     * The controller behind the two pieces of Spring Security that decide a refusal's status code:
     * the {@code @PreAuthorize} interceptor, and the filter that translates what it throws.
     */
    private static MockMvc secured(Object controller) {
        ProxyFactory factory = new ProxyFactory(controller);
        factory.setProxyTargetClass(true);
        factory.addAdvisor(AuthorizationManagerBeforeMethodInterceptor.preAuthorize());

        ExceptionTranslationFilter refusals =
                new ExceptionTranslationFilter(new BearerTokenAuthenticationEntryPoint());
        refusals.setAccessDeniedHandler(new BearerTokenAccessDeniedHandler());

        return MockMvcBuilders.standaloneSetup(factory.getProxy())
                .addFilters(refusals)
                .build();
    }

    private static void signedInAs(String subject, String... roles) {
        Jwt jwt = Jwt.withTokenValue("token")
                .header("alg", "none")
                .subject(subject)
                .build();
        List<GrantedAuthority> authorities = Arrays.stream(roles)
                .<GrantedAuthority>map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .toList();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(jwt, authorities));
    }

    private static Settings allFromConfig() {
        Map<Kind, KindDecision> byKind = new EnumMap<>(Kind.class);
        for (Kind kind : Kind.values()) {
            byKind.put(kind, new KindDecision(false, AutoApprovalSource.CONFIG));
        }
        return new Settings(byKind, null, null);
    }

    private static Settings settings(KindDecision rider, KindDecision merchant,
                                     KindDecision carrier, String by, Instant at) {
        Map<Kind, KindDecision> byKind = new EnumMap<>(Kind.class);
        byKind.put(Kind.RIDER, rider);
        byKind.put(Kind.MERCHANT, merchant);
        byKind.put(Kind.CARRIER, carrier);
        return new Settings(byKind, by, at);
    }

    @Nested
    @DisplayName("refusals")
    class Refusals {

        @Test
        @DisplayName("reading without a token is a 401")
        void no_token_cannot_read() throws Exception {
            mvc.perform(get(PATH)).andExpect(status().isUnauthorized());

            verify(policy, never()).settings();
        }

        @Test
        @DisplayName("writing without a token is a 401 and changes nothing")
        void no_token_cannot_write() throws Exception {
            mvc.perform(put(PATH)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"rider\": true, \"merchant\": true, \"carrier\": true}"))
                    .andExpect(status().isUnauthorized());

            verify(policy, never()).update(anyBoolean(), anyBoolean(), anyBoolean(), anyString());
        }

        /**
         * A shopper is signed in, so this is a 403 and not a 401 — and the distinction is the point
         * of the token check: they are somebody, they are simply not somebody who may see this.
         */
        @Test
        @DisplayName("a CUSTOMER token is a 403 on both endpoints")
        void a_customer_is_refused() throws Exception {
            signedInAs("keycloak-sub-shopper", "CUSTOMER");

            mvc.perform(get(PATH)).andExpect(status().isForbidden());
            mvc.perform(put(PATH)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"rider\": true, \"merchant\": true, \"carrier\": true}"))
                    .andExpect(status().isForbidden());

            verify(policy, never()).settings();
            verify(policy, never()).update(anyBoolean(), anyBoolean(), anyBoolean(), anyString());
        }

        /** A partner must not be able to switch off the review of their own competitors. */
        @Test
        @DisplayName("a MERCHANT token is a 403 on both endpoints")
        void a_merchant_is_refused() throws Exception {
            signedInAs("keycloak-sub-merchant", "MERCHANT");

            mvc.perform(get(PATH)).andExpect(status().isForbidden());
            mvc.perform(put(PATH)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"rider\": true, \"merchant\": true, \"carrier\": true}"))
                    .andExpect(status().isForbidden());

            verify(policy, never()).settings();
            verify(policy, never()).update(anyBoolean(), anyBoolean(), anyBoolean(), anyString());
        }

        /**
         * A missing field is refused rather than read as false. With a primitive on the record this
         * request would have switched merchant auto-approval OFF and answered 200, which is the
         * kind of success nobody notices.
         */
        @Test
        @DisplayName("a body missing a kind is a 400 and nothing is written")
        void a_missing_kind_is_refused() throws Exception {
            signedInAs(BACKOFFICE, "BACKOFFICE");

            mvc.perform(put(PATH)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"rider\": true, \"carrier\": false}"))
                    .andExpect(status().isBadRequest());

            verify(policy, never()).update(anyBoolean(), anyBoolean(), anyBoolean(), anyString());
        }

        @Test
        @DisplayName("a null kind is a 400 — the same refusal as leaving it out")
        void an_explicit_null_is_refused() throws Exception {
            signedInAs(BACKOFFICE, "BACKOFFICE");

            mvc.perform(put(PATH)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"rider\": true, \"merchant\": null, \"carrier\": false}"))
                    .andExpect(status().isBadRequest());

            verify(policy, never()).update(anyBoolean(), anyBoolean(), anyBoolean(), anyString());
        }

        @Test
        @DisplayName("a value that is not a boolean is a 400")
        void a_non_boolean_is_refused() throws Exception {
            signedInAs(BACKOFFICE, "BACKOFFICE");

            mvc.perform(put(PATH)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"rider\": \"yes please\", \"merchant\": false,"
                                    + " \"carrier\": false}"))
                    .andExpect(status().isBadRequest());

            verify(policy, never()).update(anyBoolean(), anyBoolean(), anyBoolean(), anyString());
        }

        @Test
        @DisplayName("no body at all is a 400")
        void an_empty_body_is_refused() throws Exception {
            signedInAs(BACKOFFICE, "BACKOFFICE");

            mvc.perform(put(PATH).contentType(MediaType.APPLICATION_JSON))
                    .andExpect(status().isBadRequest());

            verify(policy, never()).update(anyBoolean(), anyBoolean(), anyBoolean(), anyString());
        }
    }

    @Nested
    @DisplayName("the contract the portal builds against")
    class Contract {

        @Test
        @DisplayName("an untouched deployment reads every kind as CONFIG with no last change")
        void nothing_decided_reads_as_config() throws Exception {
            signedInAs(BACKOFFICE, "BACKOFFICE");

            mvc.perform(get(PATH))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.rider.automatic").value(false))
                    .andExpect(jsonPath("$.rider.source").value("CONFIG"))
                    .andExpect(jsonPath("$.merchant.source").value("CONFIG"))
                    .andExpect(jsonPath("$.carrier.source").value("CONFIG"))
                    // Present and null, not absent — and asserted with value(nullValue()) rather
                    // than doesNotExist(), which passes for both and so pins neither. The contract
                    // says these keys are always there; if a later @JsonInclude(NON_NULL) tidy-up
                    // dropped them, the portal would read a body it was never shown and this test
                    // is the only thing standing in the way.
                    .andExpect(jsonPath("$.lastChangedBy").value(nullValue()))
                    .andExpect(jsonPath("$.lastChangedAt").value(nullValue()));
        }

        @Test
        @DisplayName("a decided kind reads as PORTAL beside one that is still CONFIG")
        void portal_and_config_side_by_side() throws Exception {
            when(policy.settings()).thenReturn(settings(
                    new KindDecision(true, AutoApprovalSource.PORTAL),
                    new KindDecision(true, AutoApprovalSource.PORTAL),
                    new KindDecision(false, AutoApprovalSource.CONFIG),
                    BACKOFFICE, Instant.parse("2026-08-29T10:11:12Z")));

            signedInAs(BACKOFFICE, "BACKOFFICE");
            mvc.perform(get(PATH))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.rider.automatic").value(true))
                    .andExpect(jsonPath("$.rider.source").value("PORTAL"))
                    .andExpect(jsonPath("$.merchant.automatic").value(true))
                    .andExpect(jsonPath("$.carrier.automatic").value(false))
                    .andExpect(jsonPath("$.carrier.source").value("CONFIG"))
                    .andExpect(jsonPath("$.lastChangedBy").value(BACKOFFICE))
                    // ISO-8601 UTC, which is what the portal parses.
                    .andExpect(jsonPath("$.lastChangedAt").value("2026-08-29T10:11:12Z"));
        }

        @Test
        @DisplayName("a write answers with the position that resulted, and records the caller")
        void a_write_returns_the_new_position() throws Exception {
            when(policy.update(anyBoolean(), anyBoolean(), anyBoolean(), anyString()))
                    .thenReturn(settings(
                            new KindDecision(true, AutoApprovalSource.PORTAL),
                            new KindDecision(true, AutoApprovalSource.PORTAL),
                            new KindDecision(false, AutoApprovalSource.PORTAL),
                            BACKOFFICE, Instant.parse("2026-08-29T10:11:12Z")));

            signedInAs(BACKOFFICE, "BACKOFFICE");
            mvc.perform(put(PATH)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"rider\": true, \"merchant\": true, \"carrier\": false}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.rider.automatic").value(true))
                    .andExpect(jsonPath("$.carrier.automatic").value(false))
                    .andExpect(jsonPath("$.carrier.source").value("PORTAL"))
                    .andExpect(jsonPath("$.lastChangedBy").value(BACKOFFICE));

            ArgumentCaptor<Boolean> rider = ArgumentCaptor.forClass(Boolean.class);
            ArgumentCaptor<Boolean> merchant = ArgumentCaptor.forClass(Boolean.class);
            ArgumentCaptor<Boolean> carrier = ArgumentCaptor.forClass(Boolean.class);
            ArgumentCaptor<String> actor = ArgumentCaptor.forClass(String.class);
            verify(policy).update(rider.capture(), merchant.capture(), carrier.capture(),
                    actor.capture());

            assertThat(rider.getValue()).isTrue();
            assertThat(merchant.getValue()).isTrue();
            assertThat(carrier.getValue()).isFalse();
            // The actor is the token's subject, never anything the body could have named.
            assertThat(actor.getValue()).isEqualTo(BACKOFFICE);
        }
    }
}
