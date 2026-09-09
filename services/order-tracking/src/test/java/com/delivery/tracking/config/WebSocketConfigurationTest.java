package com.delivery.tracking.config;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.MessageDeliveryException;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;

import com.delivery.tracking.config.WebSocketConfiguration.RefusalErrorHandler;
import com.delivery.tracking.config.WebSocketConfiguration.SocketRefusedException;
import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.service.TrackingService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.RETURNS_DEEP_STUBS;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * What a client may do on the live rider line, and what it is told when it may not.
 *
 * <p>The refusals matter as much as the rules. A socket that answers every rejection with the same
 * frame leaves a client author guessing between "the token expired, reconnect" and "you are not on
 * that order, stop asking" — and the app either retries forever or gives up on a session that only
 * needed refreshing. The one thing a refusal must never reveal is whether an order id exists, so
 * not-a-participant and no-such-order are held to the same words here.
 */
class WebSocketConfigurationTest {

    private static final UUID ORDER = UUID.randomUUID();
    private static final String TOPIC = "/topic/orders/" + ORDER + "/position";
    private static final String CUSTOMER = "customer-sub";
    private static final String STRANGER = "stranger-sub";

    private ChannelInterceptor interceptor;
    private JwtDecoder jwtDecoder;
    private TrackingService tracking;
    private final MessageChannel channel = mock(MessageChannel.class);

    /**
     * {@code getInterceptors()} is protected, so the test reaches it the way Spring does — from a
     * subclass — rather than reaching into the class and testing something that is not wired in.
     */
    private static class CapturingRegistration extends ChannelRegistration {
        List<ChannelInterceptor> captured() {
            return getInterceptors();
        }
    }

    @BeforeEach
    void setUp() {
        jwtDecoder = mock(JwtDecoder.class);
        tracking = mock(TrackingService.class);
        CapturingRegistration registration = new CapturingRegistration();
        new WebSocketConfiguration(jwtDecoder, tracking, "*")
                .configureClientInboundChannel(registration);
        interceptor = registration.captured().get(0);
    }

    /** An order the given user is a participant of. */
    private void orderVisibleTo(String userId) {
        when(tracking.participantsOf(ORDER)).thenReturn(Optional.of(
                new OrderParticipants(ORDER, userId, "merchant-sub", "rider-sub", "PICKED_UP")));
    }

    private static Message<byte[]> frame(StompCommand command, String destination) {
        StompHeaderAccessor accessor = StompHeaderAccessor.create(command);
        if (destination != null) {
            accessor.setDestination(destination);
        }
        return message(accessor);
    }

    /** A SUBSCRIBE from an already-connected session. */
    private static Message<byte[]> subscribeAs(String userId, String destination) {
        StompHeaderAccessor accessor = StompHeaderAccessor.create(StompCommand.SUBSCRIBE);
        accessor.setDestination(destination);
        accessor.setUser(() -> userId);
        return message(accessor);
    }

    /**
     * Builds the message the way the STOMP decoder does, mutable headers and all.
     *
     * <p>Not a detail to skip: {@code getMessageHeaders()} freezes the accessor unless it is told
     * to leave it alone, and a frozen accessor makes the CONNECT interceptor's {@code setUser}
     * throw — so a test that omitted this would report an authentication failure the running
     * service does not have.
     */
    private static Message<byte[]> message(StompHeaderAccessor accessor) {
        accessor.setLeaveMutable(true);
        return MessageBuilder.createMessage(new byte[0], accessor.getMessageHeaders());
    }

    private void send(Message<byte[]> message) {
        interceptor.preSend(message, channel);
    }

    /** The reason a client would actually read off the wire for a given refusal. */
    private static String errorFrameMessage(Throwable thrown) {
        Message<byte[]> error = new RefusalErrorHandler().handleClientMessageProcessingError(
                frame(StompCommand.SUBSCRIBE, TOPIC),
                // What the inbound channel wraps an interceptor's exception in before the STOMP
                // handler ever sees it.
                new MessageDeliveryException(frame(StompCommand.SUBSCRIBE, TOPIC),
                        "Failed to send message to clientInboundChannel", thrown));
        return StompHeaderAccessor.wrap(error).getMessage();
    }

    private static Throwable refusalFrom(Runnable frame) {
        return org.assertj.core.api.Assertions.catchThrowable(frame::run);
    }

    @Nested
    @DisplayName("connecting")
    class Connecting {

        @Test
        @DisplayName("without a bearer token is refused rather than allowed through as anonymous")
        void an_unauthenticated_connect_is_refused() {
            assertThatThrownBy(() -> send(frame(StompCommand.CONNECT, null)))
                    .isInstanceOf(SocketRefusedException.class)
                    .hasMessageContaining("Authorization");
        }

        @Test
        @DisplayName("with a token the realm will not vouch for is refused")
        void an_invalid_token_is_refused() {
            when(jwtDecoder.decode("bad-token")).thenThrow(new JwtException("exp claim is in the past"));

            StompHeaderAccessor accessor = StompHeaderAccessor.create(StompCommand.CONNECT);
            accessor.setNativeHeader("Authorization", "Bearer bad-token");

            assertThatThrownBy(() -> send(message(accessor)))
                    .isInstanceOf(SocketRefusedException.class)
                    .hasMessageContaining("sign in again");
        }

        /** The validator's own words name the claim that failed; that is a hint, not an answer. */
        @Test
        @DisplayName("does not repeat what the token validator said back to the client")
        void an_invalid_token_does_not_echo_the_validators_message() {
            when(jwtDecoder.decode("bad-token")).thenThrow(new JwtException("exp claim is in the past"));

            StompHeaderAccessor accessor = StompHeaderAccessor.create(StompCommand.CONNECT);
            accessor.setNativeHeader("Authorization", "Bearer bad-token");

            assertThat(errorFrameMessage(refusalFrom(() -> send(message(accessor)))))
                    .doesNotContain("exp claim");
        }

        @Test
        @DisplayName("establishes the token's subject as the principal the topic check runs against")
        void a_valid_token_becomes_the_principal() {
            when(jwtDecoder.decode("good-token")).thenReturn(
                    Jwt.withTokenValue("good-token")
                            .header("alg", "RS256")
                            .subject(CUSTOMER)
                            .build());

            StompHeaderAccessor accessor = StompHeaderAccessor.create(StompCommand.CONNECT);
            accessor.setNativeHeader("Authorization", "Bearer good-token");

            send(message(accessor));

            assertThat(accessor.getUser()).isNotNull();
            assertThat(accessor.getUser().getName()).isEqualTo(CUSTOMER);
        }
    }

    @Nested
    @DisplayName("subscribing")
    class Subscribing {

        @Test
        @DisplayName("to an order you are on is allowed")
        void a_participants_own_order_is_allowed() {
            orderVisibleTo(CUSTOMER);

            assertThatCode(() -> send(subscribeAs(CUSTOMER, TOPIC))).doesNotThrowAnyException();
        }

        @Test
        @DisplayName("to somebody else's order is refused")
        void another_customers_order_is_refused() {
            orderVisibleTo(CUSTOMER);

            assertThatThrownBy(() -> send(subscribeAs(STRANGER, TOPIC)))
                    .isInstanceOf(SocketRefusedException.class);
        }

        /**
         * The refusal is a client-facing sentence, but it is the same sentence whether the order is
         * someone else's or was never heard of — otherwise the socket becomes an oracle for which
         * order ids exist, which is precisely what the REST reads answer 404 to avoid.
         */
        @Test
        @DisplayName("says the same thing for an order that is not yours and one that does not exist")
        void the_refusal_does_not_reveal_whether_the_order_exists() {
            orderVisibleTo(CUSTOMER);
            String notYours = errorFrameMessage(refusalFrom(() -> send(subscribeAs(STRANGER, TOPIC))));

            when(tracking.participantsOf(ORDER)).thenReturn(Optional.empty());
            String noSuchOrder = errorFrameMessage(refusalFrom(() -> send(subscribeAs(STRANGER, TOPIC))));

            assertThat(notYours).isEqualTo(noSuchOrder);
        }

        /** An id echoed back into a frame a client renders is untrusted text, as on the REST side. */
        @Test
        @DisplayName("does not echo the order id back to the client")
        void the_refusal_does_not_echo_the_order_id() {
            when(tracking.participantsOf(ORDER)).thenReturn(Optional.empty());

            assertThat(errorFrameMessage(refusalFrom(() -> send(subscribeAs(STRANGER, TOPIC)))))
                    .doesNotContain(ORDER.toString());
        }

        @Test
        @DisplayName("to a destination that is not an order topic is refused")
        void a_foreign_destination_is_refused() {
            assertThatThrownBy(() -> send(subscribeAs(CUSTOMER, "/topic/orders")))
                    .isInstanceOf(SocketRefusedException.class)
                    .hasMessageContaining("/topic/orders/{id}/position");
        }

        @Test
        @DisplayName("to nothing at all is refused rather than treated as a wildcard")
        void a_missing_destination_is_refused() {
            assertThatThrownBy(() -> send(frame(StompCommand.SUBSCRIBE, null)))
                    .isInstanceOf(SocketRefusedException.class);
        }

        /**
         * The topic pattern accepts 36 hex-and-dash characters, which is a wider set than the ids
         * that parse. Left alone the parser's own failure escapes as an unexplained frame.
         */
        @Test
        @DisplayName("to a topic whose id only looks like a UUID is refused as a bad destination")
        void an_unparseable_order_id_is_refused_as_a_bad_destination() {
            String destination = "/topic/orders/------------------------------------/position";

            assertThat(errorFrameMessage(refusalFrom(() -> send(subscribeAs(CUSTOMER, destination)))))
                    .isEqualTo("Subscriptions are only allowed on /topic/orders/{id}/position");
        }

        @Test
        @DisplayName("before connecting is refused, since there is no principal to check against")
        void a_subscribe_before_connect_is_refused() {
            assertThatThrownBy(() -> send(frame(StompCommand.SUBSCRIBE, TOPIC)))
                    .isInstanceOf(SocketRefusedException.class)
                    .hasMessageContaining("CONNECT");
        }
    }

    @Nested
    @DisplayName("publishing from a client")
    class Publishing {

        /**
         * A simple broker relays a client SEND to that destination's subscribers, which would let
         * any connected user paint a position onto somebody's map with no rider check and nothing
         * recorded. Positions arrive over REST, where the assignment check applies.
         */
        @Test
        @DisplayName("is refused outright and says where positions actually go")
        void a_client_send_is_refused() {
            assertThatThrownBy(() -> send(frame(StompCommand.SEND, TOPIC)))
                    .isInstanceOf(SocketRefusedException.class)
                    .hasMessageContaining("REST");
        }
    }

    @Nested
    @DisplayName("the frames a client uses to manage its own session")
    class SessionHousekeeping {

        @Test
        @DisplayName("pass through untouched, since they name no destination worth policing")
        void pass_through() {
            assertThatCode(() -> send(frame(StompCommand.DISCONNECT, null)))
                    .doesNotThrowAnyException();
            assertThatCode(() -> send(frame(StompCommand.UNSUBSCRIBE, null)))
                    .doesNotThrowAnyException();
        }
    }

    /**
     * The error frame is where the whole point lands: a reason a client can branch on.
     *
     * <p>The interceptor throws from inside the inbound channel's send, so what reaches the STOMP
     * handler is the channel's delivery wrapper. Without the unwrapping below every refusal on this
     * socket is one identical frame carrying "Failed to send message to clientInboundChannel".
     */
    @Nested
    @DisplayName("the ERROR frame a refusal produces")
    class ErrorFrames {

        @Test
        @DisplayName("carries the refusal's own reason, not the channel's wrapper")
        void carries_the_reason() {
            assertThat(errorFrameMessage(refusalFrom(() -> send(frame(StompCommand.CONNECT, null)))))
                    .isEqualTo("Send an Authorization: Bearer header on the CONNECT frame")
                    .doesNotContain("clientInboundChannel");
        }

        /** The failure this whole finding is about: two very different problems, one frame. */
        @Test
        @DisplayName("tells an expired session apart from an order that is not yours")
        void distinguishes_the_refusals_a_client_must_act_on_differently() {
            when(jwtDecoder.decode("bad-token")).thenThrow(new JwtException("nope"));
            StompHeaderAccessor connect = StompHeaderAccessor.create(StompCommand.CONNECT);
            connect.setNativeHeader("Authorization", "Bearer bad-token");
            String expired = errorFrameMessage(refusalFrom(() -> send(message(connect))));

            when(tracking.participantsOf(ORDER)).thenReturn(Optional.empty());
            String notYours = errorFrameMessage(refusalFrom(() -> send(subscribeAs(STRANGER, TOPIC))));

            assertThat(expired).isNotEqualTo(notYours);
        }

        @Test
        @DisplayName("tells a refused SEND apart from a refused destination")
        void distinguishes_the_two_client_mistakes() {
            String send = errorFrameMessage(refusalFrom(() -> send(frame(StompCommand.SEND, TOPIC))));
            String destination = errorFrameMessage(
                    refusalFrom(() -> send(subscribeAs(CUSTOMER, "/topic/everything"))));

            assertThat(send).isNotEqualTo(destination);
        }

        /** A fault is not an answer: its message names internals and belongs in the log only. */
        @Test
        @DisplayName("says nothing specific when the failure was not a refusal")
        void an_unexpected_failure_is_not_narrated_to_the_client() {
            String reported = errorFrameMessage(new IllegalStateException("redis pool exhausted"));

            assertThat(reported)
                    .doesNotContain("redis pool exhausted")
                    .doesNotContain("clientInboundChannel");
        }
    }

    /**
     * A reason nothing carries is a reason nobody reads. This is the one link the mocked tests
     * above cannot exercise, since the handler is only consulted through the STOMP endpoint
     * registration Spring performs at startup.
     */
    @Test
    @DisplayName("the refusal-aware error handler is the one registered on the endpoint")
    void the_error_handler_is_registered() {
        StompEndpointRegistry registry = mock(StompEndpointRegistry.class, RETURNS_DEEP_STUBS);

        new WebSocketConfiguration(jwtDecoder, tracking, "*").registerStompEndpoints(registry);

        verify(registry).setErrorHandler(org.mockito.ArgumentMatchers.any(RefusalErrorHandler.class));
    }
}
