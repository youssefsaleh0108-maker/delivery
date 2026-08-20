package com.delivery.gateway;

import org.springframework.cloud.gateway.filter.ratelimit.KeyResolver;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.ReactiveSecurityContextHolder;
import org.springframework.security.core.context.SecurityContext;

import reactor.core.publisher.Mono;

/**
 * Rate-limit buckets for the Gateway.
 *
 * <p>Keyed on the authenticated user rather than the source IP: mobile clients behind carrier NAT
 * share an IP, so IP-keyed limits would let one abusive user throttle a whole network's worth of
 * customers. Unauthenticated traffic falls back to IP, which is all that's available before a token
 * has been presented.
 */
@Configuration(proxyBeanMethods = false)
public class RateLimiterConfiguration {

    private static final String ANONYMOUS_PREFIX = "ip:";
    private static final String USER_PREFIX = "user:";

    @Bean
    @Primary
    public KeyResolver userKeyResolver() {
        return exchange -> ReactiveSecurityContextHolder.getContext()
                .map(SecurityContext::getAuthentication)
                .filter(Authentication::isAuthenticated)
                .map(authentication -> USER_PREFIX + authentication.getName())
                .switchIfEmpty(Mono.fromSupplier(() -> ANONYMOUS_PREFIX + clientAddress(exchange)));
    }

    private static String clientAddress(org.springframework.web.server.ServerWebExchange exchange) {
        return exchange.getRequest().getRemoteAddress() == null
                ? "unknown"
                : exchange.getRequest().getRemoteAddress().getAddress().getHostAddress();
    }
}
