package com.delivery.tracking.config;

import java.security.Principal;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;
import org.springframework.web.socket.messaging.StompSubProtocolErrorHandler;

import com.delivery.tracking.service.TrackingService;

/**
 * STOMP over WebSocket for the live rider line: every recorded ping is pushed to whoever is
 * watching that order, so the customer's map moves the moment the rider does instead of on the
 * next poll. The REST history endpoint stays the durable read; this socket is delivery only, and
 * a dropped connection loses nothing the next refetch will not recover.
 *
 * <p>The shape deliberately mirrors App Notification's socket (the platform's first): token
 * validated on the STOMP CONNECT frame rather than the handshake (a browser WebSocket cannot set
 * upgrade headers, and a query-string token would sit in access logs), SEND refused outright, and
 * subscriptions policed. The one difference is the authorisation unit: notifications are
 * per-user queues, positions are per-ORDER topics — so SUBSCRIBE here checks the same
 * participant rule the history endpoint enforces, and an order id you are not part of answers
 * with an error frame, not with somebody else's rider.
 *
 * <p>Every refusal below carries its own reason to the client. Left to itself the STOMP handler
 * reports whatever the inbound channel threw, which is the channel's own "failed to send" wrapper
 * — one frame, identical for an expired token and for someone else's order, so a client cannot
 * tell "reconnect after signing in again" from "stop asking for this order". What a refusal must
 * still never say is whether an order id exists: not-a-participant and no-such-order answer the
 * same words, exactly as the REST reads do.
 */
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfiguration implements WebSocketMessageBrokerConfigurer {

    private static final Logger log = LoggerFactory.getLogger(WebSocketConfiguration.class);

    /** The one destination family a client may subscribe to. */
    static final Pattern ORDER_TOPIC =
            Pattern.compile("^/topic/orders/([0-9a-fA-F-]{36})/position$");

    /** Where the CONNECT-time roles live for the SUBSCRIBE check. */
    static final String ROLES_ATTR = "delivery.roles";

    private final JwtDecoder jwtDecoder;
    private final TrackingService tracking;
    private final List<String> allowedOrigins;

    public WebSocketConfiguration(JwtDecoder jwtDecoder,
                                  TrackingService tracking,
                                  @Value("${delivery.websocket.allowed-origins:*}") String origins) {
        this.jwtDecoder = jwtDecoder;
        this.tracking = tracking;
        this.allowedOrigins = List.of(origins.split(","));
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        registry.setErrorHandler(new RefusalErrorHandler());
        registry.addEndpoint("/ws/tracking")
                .setAllowedOriginPatterns(allowedOrigins.toArray(String[]::new))
                .withSockJS();
    }

    @Override
    public void configureMessageBroker(MessageBrokerRegistry registry) {
        // In-memory simple broker, single instance — the same trade App Notification records.
        // Scaling past one instance moves this to a shared relay; the position itself is durable
        // in Redis and Postgres either way, so the failure mode is a missed live frame.
        registry.enableSimpleBroker("/topic");
    }

    @Override
    public void configureClientInboundChannel(ChannelRegistration registration) {
        registration.interceptors(new ChannelInterceptor() {
            @Override
            public Message<?> preSend(Message<?> message, MessageChannel channel) {
                StompHeaderAccessor accessor =
                        MessageHeaderAccessor.getAccessor(message, StompHeaderAccessor.class);
                if (accessor == null || accessor.getCommand() == null) {
                    return message;
                }
                switch (accessor.getCommand()) {
                    case CONNECT -> authenticate(accessor);
                    case SUBSCRIBE -> requireParticipant(accessor);
                    case SEND -> throw new SocketRefusedException(
                            "This socket does not accept client SEND frames; riders ping over REST");
                    default -> {
                        // Session management frames carry nothing worth policing.
                    }
                }
                return message;
            }

            private void authenticate(StompHeaderAccessor accessor) {
                String authorization = accessor.getFirstNativeHeader("Authorization");
                if (authorization == null || !authorization.startsWith("Bearer ")) {
                    throw new SocketRefusedException(
                            "Send an Authorization: Bearer header on the CONNECT frame");
                }
                try {
                    Jwt jwt = jwtDecoder.decode(authorization.substring("Bearer ".length()));
                    String subject = jwt.getSubject();
                    accessor.setUser((Principal) () -> subject);
                    // Roles ride the session for the SUBSCRIBE check — BACKOFFICE watches any
                    // order, the same as on the history endpoint.
                    Map<String, Object> realmAccess = jwt.getClaimAsMap("realm_access");
                    Object roles = realmAccess == null ? null : realmAccess.get("roles");
                    if (accessor.getSessionAttributes() != null) {
                        accessor.getSessionAttributes()
                                .put(ROLES_ATTR, roles == null ? List.of() : roles);
                    }
                    log.debug("Tracking socket authenticated for {}", subject);
                } catch (Exception e) {
                    // One answer for every way a token can fail to decode. The cause is logged and
                    // never sent: a validation message names the claim that failed, and telling an
                    // unauthenticated caller which one is a free hint at forging the next attempt.
                    log.debug("Tracking socket CONNECT rejected", e);
                    throw new SocketRefusedException(
                            "Your session is no longer valid; sign in again and reconnect", e);
                }
            }

            private void requireParticipant(StompHeaderAccessor accessor) {
                String destination = accessor.getDestination();
                Matcher topic = destination == null
                        ? null : ORDER_TOPIC.matcher(destination);
                if (topic == null || !topic.matches()) {
                    throw new SocketRefusedException(
                            "Subscriptions are only allowed on /topic/orders/{id}/position");
                }
                Principal user = accessor.getUser();
                if (user == null) {
                    throw new SocketRefusedException("Send a CONNECT frame before subscribing");
                }
                boolean backoffice = false;
                Map<String, Object> attrs = accessor.getSessionAttributes();
                if (attrs != null && attrs.get(ROLES_ATTR) instanceof List<?> roles) {
                    backoffice = roles.contains("BACKOFFICE");
                }
                UUID orderId;
                try {
                    orderId = UUID.fromString(topic.group(1));
                } catch (IllegalArgumentException e) {
                    // The pattern accepts 36 hex-and-dash characters, which is not the same set as
                    // the UUIDs java can parse. Answered as a bad destination rather than left to
                    // surface as whatever the parser threw.
                    throw new SocketRefusedException(
                            "Subscriptions are only allowed on /topic/orders/{id}/position", e);
                }
                boolean visible = backoffice || tracking.participantsOf(orderId)
                        .map(p -> p.isVisibleTo(user.getName()))
                        .orElse(false);
                if (!visible) {
                    // The same answer the REST reads give, and the same answer for both branches:
                    // an order you are not part of is indistinguishable from one that does not
                    // exist, and the id is not echoed back into a frame a client renders.
                    throw new SocketRefusedException("That order is not available on this socket");
                }
            }
        });
    }

    /**
     * A refusal whose message is meant for the client on the other end of the socket.
     *
     * <p>Distinct type rather than a plain runtime exception so {@link RefusalErrorHandler} can
     * tell a reason that was written for a client from a failure that was not: anything else
     * reaching the handler is a bug, and a bug's message is not something to put on the wire.
     */
    static class SocketRefusedException extends RuntimeException {

        SocketRefusedException(String reason) {
            super(reason);
        }

        SocketRefusedException(String reason, Throwable cause) {
            super(reason, cause);
        }
    }

    /**
     * Puts the refusal's own reason on the ERROR frame.
     *
     * <p>The interceptor throws from inside the inbound channel's send, so by the time the STOMP
     * handler sees it the reason is wrapped in the channel's delivery exception and the default
     * handler reports the wrapper. Unwrapping is what makes every refusal distinguishable.
     *
     * <p>Anything that is not a refusal is a fault rather than an answer, and its message is
     * framework text naming internals, so the client gets one fixed sentence instead. The original
     * is already logged by the STOMP handler before it gets here.
     */
    static class RefusalErrorHandler extends StompSubProtocolErrorHandler {

        @Override
        public Message<byte[]> handleClientMessageProcessingError(Message<byte[]> clientMessage,
                                                                  Throwable ex) {
            SocketRefusedException refusal = refusalIn(ex);
            return super.handleClientMessageProcessingError(clientMessage,
                    refusal != null ? refusal
                            : new SocketRefusedException("That frame could not be processed"));
        }

        private static SocketRefusedException refusalIn(Throwable ex) {
            for (Throwable cause = ex; cause != null; cause = cause.getCause()) {
                if (cause instanceof SocketRefusedException refusal) {
                    return refusal;
                }
                if (cause == cause.getCause()) {
                    break;
                }
            }
            return null;
        }
    }
}
