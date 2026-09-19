package com.delivery.tracking.api;

import java.time.Instant;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.MediaType;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.tracking.service.DutySessionService;
import com.delivery.tracking.service.EtaService;
import com.delivery.tracking.service.Fix;
import com.delivery.tracking.service.FixPolicy;
import com.delivery.tracking.service.PresenceService;
import com.delivery.tracking.service.TrackingService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Who may report a rider's position, and what each refusal tells the handset.
 *
 * <p>Two routes take a position — the order-scoped ping and the rider's own — and one handset sends
 * both, so they are pinned together. Standalone MockMvc: method security is NOT wired, so every
 * role refusal below holds because the handler checks the role itself as well, which is the point.
 * The finer rules (assigned rider, on duty, a believable fix) live in the services and have their
 * own suites; here they are only seen as the status and body the app receives.
 */
@DisplayName("who may report a rider's position")
class PingRoutesAccessTest {

    private static final String RIDER = "rider-sub";
    private static final UUID ORDER = UUID.fromString("0f0e0d0c-0000-4000-8000-000000000001");
    private static final String BODY = """
            {"lat":33.8938,"lng":35.5018,"accuracyM":6.5,"recordedAt":"2026-09-19T10:00:00Z"}""";
    /** What every app build before the fix time existed sends — it must keep working. */
    private static final String OLD_APP_BODY = """
            {"lat":33.8938,"lng":35.5018,"accuracyM":8}""";

    private TrackingService tracking;
    private PresenceService presence;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        tracking = mock(TrackingService.class);
        presence = mock(PresenceService.class);
        mvc = MockMvcBuilders.standaloneSetup(
                        new TrackingController(tracking, mock(EtaService.class),
                                mock(SimpMessagingTemplate.class)),
                        new RiderPresenceController(presence, mock(DutySessionService.class)))
                .setControllerAdvice(new PingProblems())
                .build();

        when(tracking.ping(any(UUID.class), anyString(), any(Fix.class))).thenAnswer(call -> {
            Fix fix = call.getArgument(2);
            return new TrackingService.Position(call.getArgument(0), call.getArgument(1),
                    fix.lat(), fix.lng(), fix.accuracyM(), Instant.now());
        });
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static void signedInAs(String subject, String... roles) {
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(subject).build();
        List<GrantedAuthority> authorities = Arrays.stream(roles)
                .<GrantedAuthority>map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .toList();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(jwt, authorities));
    }

    private org.springframework.test.web.servlet.ResultActions orderPing(String body)
            throws Exception {
        return mvc.perform(post("/api/tracking/orders/" + ORDER + "/ping")
                .contentType(MediaType.APPLICATION_JSON).content(body));
    }

    private org.springframework.test.web.servlet.ResultActions ownPing(String body)
            throws Exception {
        return mvc.perform(post("/api/tracking/riders/me/ping")
                .contentType(MediaType.APPLICATION_JSON).content(body));
    }

    @Nested
    @DisplayName("who is refused")
    class Callers {

        @Test
        void anonymous_callers_are_refused_on_both_routes() throws Exception {
            orderPing(BODY).andExpect(status().isUnauthorized());
            ownPing(BODY).andExpect(status().isUnauthorized());

            verifyNoInteractions(tracking, presence);
        }

        /**
         * A customer's token must not be able to write a position under the customer's own name —
         * on the order they are watching least of all.
         */
        @Test
        void a_customer_is_refused_on_both_routes() throws Exception {
            signedInAs("customer-sub", "CUSTOMER");

            orderPing(BODY).andExpect(status().isForbidden());
            ownPing(BODY).andExpect(status().isForbidden());

            verifyNoInteractions(tracking, presence);
        }

        @Test
        void a_merchant_or_a_dispatcher_is_refused() throws Exception {
            signedInAs("staff-sub", "MERCHANT", "CARRIER", "BACKOFFICE");

            orderPing(BODY).andExpect(status().isForbidden());
            ownPing(BODY).andExpect(status().isForbidden());

            verifyNoInteractions(tracking, presence);
        }

        /** Not assigned to the order: the service's 404, unchanged by any of this. */
        @Test
        void a_rider_who_is_not_on_the_order_gets_the_same_not_found_as_before() throws Exception {
            signedInAs("other-rider", "DELIVERY");
            when(tracking.ping(eq(ORDER), eq("other-rider"), any(Fix.class)))
                    .thenThrow(new TrackingService.TrackingNotFoundException(ORDER));

            orderPing(BODY).andExpect(status().isNotFound());
        }

        /** Off duty with nothing in hand: told why, so the app can stop and say so. */
        @Test
        void a_rider_who_is_off_duty_with_no_order_gets_a_conflict() throws Exception {
            signedInAs(RIDER, "DELIVERY");
            when(presence.recordOffOrderFix(eq(RIDER), any(Fix.class)))
                    .thenThrow(new PresenceService.OffDutyException());

            ownPing(BODY)
                    .andExpect(status().isConflict())
                    .andExpect(jsonPath("$.title").value("Off duty"));
        }
    }

    @Nested
    @DisplayName("what a rider's report carries")
    class Reports {

        @Test
        void a_rider_reports_on_their_order_with_the_phones_fix_time() throws Exception {
            signedInAs(RIDER, "DELIVERY");
            ArgumentCaptor<Fix> fix = ArgumentCaptor.forClass(Fix.class);

            orderPing(BODY).andExpect(status().isAccepted());

            verify(tracking).ping(eq(ORDER), eq(RIDER), fix.capture());
            assertThat(fix.getValue()).isEqualTo(new Fix(33.8938, 35.5018, 6.5f,
                    Instant.parse("2026-09-19T10:00:00Z")));
        }

        @Test
        void a_rider_reports_between_jobs_in_their_own_name_only() throws Exception {
            signedInAs(RIDER, "DELIVERY");

            ownPing(BODY).andExpect(status().isAccepted());

            verify(presence).recordOffOrderFix(eq(RIDER), eq(new Fix(33.8938, 35.5018, 6.5f,
                    Instant.parse("2026-09-19T10:00:00Z"))));
        }

        /** The fix time is additive: an app that predates it is not refused for leaving it out. */
        @Test
        void a_report_from_an_older_app_with_no_fix_time_is_still_accepted() throws Exception {
            signedInAs(RIDER, "DELIVERY");

            orderPing(OLD_APP_BODY).andExpect(status().isAccepted());
            ownPing(OLD_APP_BODY).andExpect(status().isAccepted());

            verify(tracking).ping(ORDER, RIDER, Fix.untimed(33.8938, 35.5018, 8f));
            verify(presence).recordOffOrderFix(RIDER, Fix.untimed(33.8938, 35.5018, 8f));
        }

        @Test
        void a_negative_accuracy_is_malformed() throws Exception {
            signedInAs(RIDER, "DELIVERY");

            orderPing("""
                    {"lat":33.8938,"lng":35.5018,"accuracyM":-4}""")
                    .andExpect(status().isBadRequest());
            ownPing("""
                    {"lat":33.8938,"lng":35.5018,"accuracyM":-4}""")
                    .andExpect(status().isBadRequest());

            verifyNoInteractions(tracking, presence);
        }

        /**
         * A fix that is not believed answers 422 with a machine-readable reason: the app counts the
         * clock ones and tells the rider their phone's time is wrong.
         */
        @Test
        void a_fix_that_is_not_believed_says_why() throws Exception {
            signedInAs(RIDER, "DELIVERY");
            when(tracking.ping(eq(ORDER), eq(RIDER), any(Fix.class))).thenThrow(
                    new FixPolicy.FixRejectedException(FixPolicy.Reason.FIX_IN_FUTURE));
            when(presence.recordOffOrderFix(eq(RIDER), any(Fix.class))).thenThrow(
                    new FixPolicy.FixRejectedException(FixPolicy.Reason.ACCURACY_TOO_LOW));

            orderPing(BODY)
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.reason").value("FIX_IN_FUTURE"))
                    .andExpect(jsonPath("$.title").value("Location not recorded"));
            ownPing(BODY)
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.reason").value("ACCURACY_TOO_LOW"));
        }
    }
}
