package com.delivery.appnotification.config;

import java.security.Principal;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;

/**
 * STOMP over WebSocket for live in-app notifications (Section 9).
 *
 * <p><strong>The token is validated on CONNECT, not at the handshake.</strong> A browser WebSocket
 * cannot set an Authorization header on the upgrade request, so the usual resource-server filter
 * chain has nothing to check. Passing the token in the query string instead would put it in access
 * logs and browser history. The STOMP CONNECT frame is the first thing the client sends after the
 * socket opens and it can carry arbitrary headers, which makes it the right place.
 *
 * <p>An unauthenticated CONNECT is rejected outright rather than allowed through as anonymous. The
 * user destination prefix resolves per-principal, so a connection with no principal would have
 * nothing to deliver to anyway — failing loudly beats a socket that silently receives nothing.
 */
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfiguration implements WebSocketMessageBrokerConfigurer {

    private static final Logger log = LoggerFactory.getLogger(WebSocketConfiguration.class);

    private final JwtDecoder jwtDecoder;
    private final List<String> allowedOrigins;

    public WebSocketConfiguration(JwtDecoder jwtDecoder,
                                  @Value("${delivery.websocket.allowed-origins:*}") String origins) {
        this.jwtDecoder = jwtDecoder;
        this.allowedOrigins = List.of(origins.split(","));
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        registry.addEndpoint("/ws/notifications")
                .setAllowedOriginPatterns(allowedOrigins.toArray(String[]::new))
                // SockJS fallback for networks that block raw WebSocket upgrades - common on
                // corporate Wi-Fi, which is exactly where field staff use the app.
                .withSockJS();
    }

    @Override
    public void configureMessageBroker(MessageBrokerRegistry registry) {
        // A simple in-memory broker. Fine because each connection only ever receives its own
        // user's messages and nothing is fanned out between them. If this service is ever scaled
        // past one instance, the push has to move to a shared relay - the message is still durable
        // in Postgres either way, so the failure mode is a missed live update, not a lost message.
        registry.enableSimpleBroker("/queue");
        registry.setUserDestinationPrefix("/user");
    }

    @Override
    public void configureClientInboundChannel(ChannelRegistration registration) {
        registration.interceptors(new ChannelInterceptor() {
            @Override
            public Message<?> preSend(Message<?> message, MessageChannel channel) {
                StompHeaderAccessor accessor =
                        MessageHeaderAccessor.getAccessor(message, StompHeaderAccessor.class);

                if (accessor == null || !StompCommand.CONNECT.equals(accessor.getCommand())) {
                    return message;
                }

                String authorization = accessor.getFirstNativeHeader("Authorization");
                if (authorization == null || !authorization.startsWith("Bearer ")) {
                    throw new IllegalArgumentException("STOMP CONNECT without a bearer token");
                }

                try {
                    Jwt jwt = jwtDecoder.decode(authorization.substring("Bearer ".length()));
                    String subject = jwt.getSubject();
                    // The principal name is what convertAndSendToUser routes on, so it must be the
                    // same Keycloak sub the notification was addressed to.
                    accessor.setUser((Principal) () -> subject);
                    log.debug("WebSocket authenticated for {}", subject);

                } catch (Exception e) {
                    throw new IllegalArgumentException("STOMP CONNECT with an invalid token", e);
                }

                return message;
            }
        });
    }
}
