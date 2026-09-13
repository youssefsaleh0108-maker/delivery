package com.delivery.appnotification.client;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.util.UriUtils;

import com.delivery.appnotification.service.RoomExceptions.ProofUnavailableException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.hamcrest.Matchers.startsWith;
import static org.springframework.test.web.client.ExpectedCount.once;
import static org.springframework.test.web.client.ExpectedCount.times;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.queryParam;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * Asking Order Manager where the caller's orders were delivered: as the caller, briefly remembered,
 * and never answered with a guess.
 */
class DeliveredAreasTest {

    private static final UUID MAR_MIKHAEL = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID HAMRA = UUID.fromString("33333333-3333-3333-3333-333333333333");
    private static final Instant NOW = Instant.parse("2026-09-13T10:00:00Z");
    private static final Instant SINCE = NOW.minus(Duration.ofDays(365));
    private static final Instant DELIVERED = Instant.parse("2026-08-30T18:40:00Z");
    private static final String ANSWER = """
            [{"zoneId":"11111111-1111-1111-1111-111111111111","lastDeliveredAt":"2026-08-30T18:40:00Z"}]
            """;

    private MockRestServiceServer server;
    private MovableClock clock;
    private DeliveredAreas areas;

    @BeforeEach
    void setUp() {
        RestClient.Builder builder = RestClient.builder().baseUrl("http://order-manager");
        server = MockRestServiceServer.bindTo(builder).build();
        clock = new MovableClock(NOW);
        areas = new DeliveredAreas(builder.build(), Duration.ofMinutes(2), clock);

        Jwt jwt = Jwt.withTokenValue("customer-token").header("alg", "none").subject("customer-sub").build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    @Test
    @DisplayName("asks with the caller's own token and the window, and reads the latest delivery per area")
    void asks_as_the_caller() {
        server.expect(once(), requestTo(startsWith("http://order-manager/api/orders/mine/delivered-zones")))
                .andExpect(method(HttpMethod.GET))
                // The caller's own token: nothing here could read anybody else's orders.
                .andExpect(header("Authorization", "Bearer customer-token"))
                // Percent-encoded on the wire (the colons), and decoded by Order Manager's MVC.
                .andExpect(queryParam("since", UriUtils.encode(SINCE.toString(), StandardCharsets.UTF_8)))
                .andRespond(withSuccess(ANSWER, MediaType.APPLICATION_JSON));

        assertThat(areas.lastDeliveryIn("customer-sub", MAR_MIKHAEL, SINCE)).contains(DELIVERED);
        assertThat(areas.lastDeliveryIn("customer-sub", HAMRA, SINCE))
                .as("No delivery in Hamra, so nothing to prove there")
                .isEmpty();
        server.verify();
    }

    @Test
    @DisplayName("reuses one caller's answer for a few minutes, then asks again")
    void remembers_briefly() {
        server.expect(times(2), requestTo(startsWith("http://order-manager/api/orders/mine/delivered-zones")))
                .andRespond(withSuccess(ANSWER, MediaType.APPLICATION_JSON));

        areas.lastDeliveryIn("customer-sub", MAR_MIKHAEL, SINCE);
        clock.advance(Duration.ofSeconds(90));
        areas.lastDeliveryIn("customer-sub", MAR_MIKHAEL, SINCE.plusSeconds(90));
        clock.advance(Duration.ofMinutes(1));
        areas.lastDeliveryIn("customer-sub", MAR_MIKHAEL, SINCE.plusSeconds(150));

        server.verify();
    }

    @Test
    @DisplayName("never hands one caller's answer to another")
    void one_answer_per_caller() {
        server.expect(times(2), requestTo(startsWith("http://order-manager/api/orders/mine/delivered-zones")))
                .andRespond(withSuccess(ANSWER, MediaType.APPLICATION_JSON));

        areas.lastDeliveryIn("customer-sub", MAR_MIKHAEL, SINCE);
        areas.lastDeliveryIn("another-customer-sub", MAR_MIKHAEL, SINCE);

        server.verify();
    }

    /** A remembered answer is minutes old; the window it is asked about has moved on by then. */
    @Test
    @DisplayName("does not count a remembered delivery that has since slid out of the window")
    void the_window_is_applied_to_a_remembered_answer() {
        Instant justInside = SINCE.plusSeconds(30);
        server.expect(once(), requestTo(startsWith("http://order-manager/api/orders/mine/delivered-zones")))
                .andRespond(withSuccess("[{\"zoneId\":\"" + MAR_MIKHAEL + "\",\"lastDeliveredAt\":\""
                        + justInside + "\"}]", MediaType.APPLICATION_JSON));

        assertThat(areas.lastDeliveryIn("customer-sub", MAR_MIKHAEL, SINCE)).contains(justInside);
        clock.advance(Duration.ofMinutes(1));
        assertThat(areas.lastDeliveryIn("customer-sub", MAR_MIKHAEL, SINCE.plusSeconds(60))).isEmpty();
        server.verify();
    }

    /** Neither answer is safe to make up: see ProofUnavailableException. */
    @Test
    @DisplayName("an Order Manager failure is unavailable, not \"no deliveries\", and is not remembered")
    void fails_closed_and_forgets_the_failure() {
        server.expect(once(), requestTo(startsWith("http://order-manager/api/orders/mine/delivered-zones")))
                .andRespond(withServerError());
        server.expect(once(), requestTo(startsWith("http://order-manager/api/orders/mine/delivered-zones")))
                .andRespond(withSuccess(ANSWER, MediaType.APPLICATION_JSON));

        assertThatThrownBy(() -> areas.lastDeliveryIn("customer-sub", MAR_MIKHAEL, SINCE))
                .isInstanceOf(ProofUnavailableException.class);
        assertThat(areas.lastDeliveryIn("customer-sub", MAR_MIKHAEL, SINCE)).contains(DELIVERED);
        server.verify();
    }

    private static final class MovableClock extends Clock {
        private Instant now;

        MovableClock(Instant now) {
            this.now = now;
        }

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
