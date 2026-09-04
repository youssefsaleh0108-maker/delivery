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
                    case SEND -> throw new IllegalArgumentException(
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
                    throw new IllegalArgumentException("STOMP CONNECT without a bearer token");
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
                    throw new IllegalArgumentException("STOMP CONNECT with an invalid token", e);
                }
            }

            private void requireParticipant(StompHeaderAccessor accessor) {
                String destination = accessor.getDestination();
                Matcher topic = destination == null
                        ? null : ORDER_TOPIC.matcher(destination);
                if (topic == null || !topic.matches()) {
                    throw new IllegalArgumentException(
                            "Subscriptions are only allowed on /topic/orders/{id}/position");
                }
                Principal user = accessor.getUser();
                if (user == null) {
                    throw new IllegalArgumentException("SUBSCRIBE before CONNECT");
                }
                boolean backoffice = false;
                Map<String, Object> attrs = accessor.getSessionAttributes();
                if (attrs != null && attrs.get(ROLES_ATTR) instanceof List<?> roles) {
                    backoffice = roles.contains("BACKOFFICE");
                }
                UUID orderId = UUID.fromString(topic.group(1));
                boolean visible = backoffice || tracking.participantsOf(orderId)
                        .map(p -> p.isVisibleTo(user.getName()))
                        .orElse(false);
                if (!visible) {
                    // The same answer the REST reads give: an order you are not part of does not
                    // exist as far as you can tell.
                    throw new IllegalArgumentException("Unknown order " + orderId);
                }
            }
        });
    }
}
