package com.delivery.appnotification.config;

import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * What a connected client is allowed to do on the socket.
 *
 * <p>These guarantees became load-bearing when order chat gave the socket private two-party content
 * to carry. A simple broker does exactly what a STOMP client asks it to: left unguarded it will
 * relay a client's SEND to whoever is subscribed to that destination, and it will let a client
 * subscribe to any destination it can name — including the per-session queue another user's frames
 * are published to. Both of those are "a third party can read or post", expressed at the transport
 * rather than at the API.
 */
class WebSocketConfigurationTest {

    private ChannelInterceptor interceptor;
    private JwtDecoder jwtDecoder;
    private final MessageChannel channel = mock(MessageChannel.class);

    /**
     * {@code getInterceptors()} is protected, so the test reaches it the way Spring does — from a
     * subclass. Exercising the real registration rather than reaching into the class keeps this
     * honest about what is actually wired in.
     */
    private static class CapturingRegistration extends ChannelRegistration {
        List<ChannelInterceptor> captured() {
            return getInterceptors();
        }
    }

    @BeforeEach
    void setUp() {
        jwtDecoder = mock(JwtDecoder.class);
        CapturingRegistration registration = new CapturingRegistration();
        new WebSocketConfiguration(jwtDecoder, "*").configureClientInboundChannel(registration);
        interceptor = registration.captured().get(0);
    }

    private static Message<byte[]> frame(StompCommand command, String destination) {
        StompHeaderAccessor accessor = StompHeaderAccessor.create(command);
        if (destination != null) {
            accessor.setDestination(destination);
        }
        return message(accessor);
    }

    /**
     * Builds the message the way the STOMP decoder does, mutable headers and all.
     *
     * <p>Not a detail to skip: {@code getMessageHeaders()} freezes the accessor unless it is told
     * to leave it alone, and a frozen accessor makes the CONNECT interceptor's {@code setUser} throw
     * — so a test that omitted this would report an authentication failure that the running service
     * does not have.
     */
    private static Message<byte[]> message(StompHeaderAccessor accessor) {
        accessor.setLeaveMutable(true);
        return MessageBuilder.createMessage(new byte[0], accessor.getMessageHeaders());
    }

    private void send(Message<byte[]> message) {
        interceptor.preSend(message, channel);
    }

    @Nested
    @DisplayName("connecting")
    class Connecting {

        @Test
        @DisplayName("without a bearer token is refused rather than allowed through as anonymous")
        void an_unauthenticated_connect_is_refused() {
            assertThatThrownBy(() -> send(frame(StompCommand.CONNECT, null)))
                    .isInstanceOf(IllegalArgumentException.class);
        }

        @Test
        @DisplayName("with a token the realm will not vouch for is refused")
        void an_invalid_token_is_refused() {
            when(jwtDecoder.decode("bad-token")).thenThrow(new JwtException("nope"));

            StompHeaderAccessor accessor = StompHeaderAccessor.create(StompCommand.CONNECT);
            accessor.setNativeHeader("Authorization", "Bearer bad-token");

            assertThatThrownBy(() -> send(message(accessor)))
                    .isInstanceOf(IllegalArgumentException.class);
        }

        /**
         * The principal name is what {@code convertAndSendToUser} routes on, so it has to be the
         * same Keycloak sub the message was addressed to. Getting this wrong is a socket that
         * connects happily and receives nothing.
         */
        @Test
        @DisplayName("establishes the token's subject as the principal frames will be routed to")
        void a_valid_token_becomes_the_principal() {
            when(jwtDecoder.decode("good-token")).thenReturn(
                    Jwt.withTokenValue("good-token")
                            .header("alg", "RS256")
                            .subject("rider-sub")
                            .build());

            StompHeaderAccessor accessor = StompHeaderAccessor.create(StompCommand.CONNECT);
            accessor.setNativeHeader("Authorization", "Bearer good-token");

            send(message(accessor));

            assertThat(accessor.getUser()).isNotNull();
            assertThat(accessor.getUser().getName()).isEqualTo("rider-sub");
        }
    }

    @Nested
    @DisplayName("subscribing")
    class Subscribing {

        /** Spring substitutes the session's own principal, so this can only ever be your own queue. */
        @Test
        @DisplayName("to your own user destination is allowed, for chat and for notifications alike")
        void your_own_user_destination_is_allowed() {
            assertThatCode(() -> send(frame(StompCommand.SUBSCRIBE, "/user/queue/chat")))
                    .doesNotThrowAnyException();
            assertThatCode(() -> send(frame(StompCommand.SUBSCRIBE, "/user/queue/notifications")))
                    .doesNotThrowAnyException();
        }

        /**
         * The destination the user-destination handler actually publishes to. A client that could
         * name it directly would be reading somebody else's chat off the wire.
         */
        @Test
        @DisplayName("to another session's resolved broker queue is refused")
        void another_sessions_resolved_queue_is_refused() {
            assertThatThrownBy(() -> send(frame(StompCommand.SUBSCRIBE, "/queue/chat-userabc123")))
                    .isInstanceOf(IllegalArgumentException.class);
        }

        @Test
        @DisplayName("to a bare broker destination is refused, so nothing can be listened in on")
        void a_bare_broker_destination_is_refused() {
            assertThatThrownBy(() -> send(frame(StompCommand.SUBSCRIBE, "/queue/chat")))
                    .isInstanceOf(IllegalArgumentException.class);
        }

        @Test
        @DisplayName("to nothing at all is refused rather than treated as a wildcard")
        void a_missing_destination_is_refused() {
            assertThatThrownBy(() -> send(frame(StompCommand.SUBSCRIBE, null)))
                    .isInstanceOf(IllegalArgumentException.class);
        }
    }

    @Nested
    @DisplayName("publishing from a client")
    class Publishing {

        /**
         * The hole this closes: a simple broker relays a client SEND to that destination's
         * subscribers, which would let any connected user post into another user's queue with no
         * persistence, no membership check and no record of it. Chat is posted over REST, where the
         * resource server and ChatService's membership check both apply.
         */
        @Test
        @DisplayName("is refused outright, so nobody can put a message on the wire that was never stored")
        void a_client_send_is_refused() {
            assertThatThrownBy(() -> send(frame(StompCommand.SEND, "/queue/chat")))
                    .isInstanceOf(IllegalArgumentException.class);
            assertThatThrownBy(() -> send(frame(StompCommand.SEND, "/user/queue/chat")))
                    .isInstanceOf(IllegalArgumentException.class);
        }

        /** Refused, not dropped: silence would read to a client author as a delivery bug. */
        @Test
        @DisplayName("is answered with an error that says where messages actually go")
        void the_refusal_points_at_the_rest_endpoint() {
            assertThatThrownBy(() -> send(frame(StompCommand.SEND, "/queue/chat")))
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
}
