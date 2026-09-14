package com.delivery.appnotification.client;

import java.net.SocketTimeoutException;
import java.time.Instant;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import com.delivery.appnotification.client.OrderReferences.OrderReference;
import com.delivery.appnotification.service.RoomExceptions.OrderUnavailableException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.ExpectedCount.once;
import static org.springframework.test.web.client.ExpectedCount.times;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * Asking Order Manager about one order: as the caller, keeping only what a chat link is decided on,
 * never remembered, and never answered with a guess.
 */
class OrderReferencesTest {

    private static final UUID ORDER = UUID.fromString("5f0c2a9e-1111-4222-8333-444455556666");
    private static final UUID STORE = UUID.fromString("7a1b2c3d-0000-4000-8000-000000000001");
    private static final String URL = "http://order-manager/api/orders/" + ORDER;

    /** An abridged OrderResponse, with fields chat has no use for among the ones it reads. */
    private static final String DELIVERED = """
            {"id":"5f0c2a9e-1111-4222-8333-444455556666","kind":"SERVICE","customerId":"customer-sub",
             "merchantId":"merchant-sub","riderId":null,"status":"DELIVERED","totalAmount":16.00,
             "storeId":"7a1b2c3d-0000-4000-8000-000000000001","storeName":"Abu Hassan Print",
             "deliveryAddress":null,"contactPhone":"+96170123456","items":[],"actions":[],
             "placedAt":"2026-09-01T09:00:00Z","deliveredAt":"2026-09-10T12:00:00Z","cancelledAt":null,
             "fulfilment":"PICKUP","readyAt":"2026-09-09T15:00:00Z","estimatedReadyAt":"2026-09-08T09:00:00Z",
             "customerDisplayName":"Tania K."}
            """;

    private MockRestServiceServer server;
    private OrderReferences references;

    @BeforeEach
    void setUp() {
        RestClient.Builder builder = RestClient.builder().baseUrl("http://order-manager");
        server = MockRestServiceServer.bindTo(builder).build();
        references = new OrderReferences(builder.build());

        Jwt jwt = Jwt.withTokenValue("merchant-token").header("alg", "none").subject("merchant-sub").build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    @Test
    @DisplayName("reads the order every app reads, with the caller's own token, keeping what a link is decided on")
    void reads_as_the_caller() {
        server.expect(once(), requestTo(URL))
                .andExpect(method(HttpMethod.GET))
                // The caller's own token: Order Manager shows only an order that is theirs to see.
                .andExpect(header("Authorization", "Bearer merchant-token"))
                .andRespond(withSuccess(DELIVERED, MediaType.APPLICATION_JSON));

        OrderReference order = references.visibleToCaller(ORDER).orElseThrow();

        assertThat(order.id()).isEqualTo(ORDER);
        assertThat(order.storeId()).isEqualTo(STORE);
        assertThat(order.storeName()).isEqualTo("Abu Hassan Print");
        assertThat(order.customerId()).isEqualTo("customer-sub");
        assertThat(order.kind()).isEqualTo("SERVICE");
        assertThat(order.customerDisplayName()).isEqualTo("Tania K.");
        assertThat(order.placedAt()).isEqualTo(Instant.parse("2026-09-01T09:00:00Z"));
        assertThat(order.estimatedReadyAt()).isEqualTo(Instant.parse("2026-09-08T09:00:00Z"));
        assertThat(order.hasEnded()).isTrue();
        assertThat(order.endedAt()).isEqualTo(Instant.parse("2026-09-10T12:00:00Z"));
        server.verify();
    }

    @Test
    @DisplayName("an order Order Manager does not show the caller is empty, whether missing, refused or malformed")
    void not_shown_is_empty() {
        server.expect(once(), requestTo(URL)).andRespond(withStatus(HttpStatus.NOT_FOUND));
        server.expect(once(), requestTo(URL)).andRespond(withStatus(HttpStatus.FORBIDDEN));
        server.expect(once(), requestTo(URL)).andRespond(withStatus(HttpStatus.BAD_REQUEST));

        assertThat(references.visibleToCaller(ORDER)).isEmpty();
        assertThat(references.visibleToCaller(ORDER)).isEmpty();
        assertThat(references.visibleToCaller(ORDER)).isEmpty();
        server.verify();
    }

    /** Neither answer is safe to make up: see OrderUnavailableException. */
    @Test
    @DisplayName("a failure, a timeout, a rejected token, an answer about another order or one without when it was placed is unavailable, never empty")
    void fails_closed() {
        server.expect(once(), requestTo(URL)).andRespond(withServerError());
        server.expect(once(), requestTo(URL)).andRespond(request -> {
            throw new SocketTimeoutException("Read timed out");
        });
        server.expect(once(), requestTo(URL)).andRespond(withStatus(HttpStatus.UNAUTHORIZED));
        server.expect(once(), requestTo(URL)).andRespond(withSuccess(
                DELIVERED.replace(ORDER.toString(), UUID.randomUUID().toString()), MediaType.APPLICATION_JSON));
        // Without it, how long the order's shop may open a chat about it cannot be measured.
        server.expect(once(), requestTo(URL)).andRespond(withSuccess(
                DELIVERED.replace("\"placedAt\":\"2026-09-01T09:00:00Z\",", ""), MediaType.APPLICATION_JSON));

        for (int i = 0; i < 5; i++) {
            assertThatThrownBy(() -> references.visibleToCaller(ORDER))
                    .isInstanceOf(OrderUnavailableException.class);
        }
        server.verify();
    }

    @Test
    @DisplayName("asks again every time: nothing is remembered, so no refusal can ever be remembered as a yes")
    void never_remembers() {
        server.expect(times(2), requestTo(URL)).andRespond(withSuccess(DELIVERED, MediaType.APPLICATION_JSON));

        references.visibleToCaller(ORDER);
        references.visibleToCaller(ORDER);

        server.verify();
    }

    @Test
    @DisplayName("an open order has not ended; a cancelled one ended when it was cancelled")
    void when_an_order_ended() {
        Instant placedAt = Instant.parse("2026-09-01T09:00:00Z");
        Instant cancelledAt = Instant.parse("2026-09-02T08:00:00Z");
        OrderReference open = new OrderReference(ORDER, STORE, null, "customer-sub", "SERVICE", "PREPARING",
                placedAt, null, null, null, null);
        OrderReference cancelled = new OrderReference(ORDER, STORE, null, "customer-sub", "SERVICE", "CANCELLED",
                placedAt, null, null, cancelledAt, null);

        assertThat(open.hasEnded()).isFalse();
        assertThat(open.endedAt()).isNull();
        assertThat(cancelled.hasEnded()).isTrue();
        assertThat(cancelled.endedAt()).isEqualTo(cancelledAt);
    }

    /** What a shop's window for opening a chat about the order is counted from, with when it ended. */
    @Test
    @DisplayName("an order is due when its work was promised, or when it was placed if nothing was")
    void when_an_order_was_due() {
        Instant placedAt = Instant.parse("2026-09-01T09:00:00Z");
        Instant promised = Instant.parse("2026-09-04T09:00:00Z");

        assertThat(order("SERVICE", "PREPARING", placedAt, promised).dueAt()).isEqualTo(promised);
        assertThat(order("SERVICE", "PLACED", placedAt, null).dueAt())
                .as("a service order its shop has not accepted").isEqualTo(placedAt);
        assertThat(order("CATALOG", "PREPARING", placedAt, null).dueAt())
                .as("a goods order, which promises no ready time").isEqualTo(placedAt);
        assertThat(order("SERVICE", "PREPARING", placedAt, placedAt.minusSeconds(1)).dueAt())
                .as("never before it was placed").isEqualTo(placedAt);
    }

    private static OrderReference order(String kind, String status, Instant placedAt, Instant estimatedReadyAt) {
        return new OrderReference(ORDER, STORE, null, "customer-sub", kind, status, placedAt, estimatedReadyAt,
                null, null, null);
    }
}
