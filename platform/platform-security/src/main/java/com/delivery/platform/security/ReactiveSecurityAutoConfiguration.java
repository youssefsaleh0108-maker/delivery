package com.delivery.platform.security;

import org.springframework.boot.autoconfigure.condition.ConditionalOnClass;
import org.springframework.boot.autoconfigure.security.oauth2.resource.OAuth2ResourceServerProperties;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.method.configuration.EnableReactiveMethodSecurity;
import org.springframework.security.config.web.server.ServerHttpSecurity;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusReactiveJwtDecoder;
import org.springframework.security.oauth2.jwt.ReactiveJwtDecoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.oauth2.server.resource.authentication.ReactiveJwtAuthenticationConverterAdapter;
import org.springframework.security.web.server.SecurityWebFilterChain;
import org.springframework.security.web.server.util.matcher.ServerWebExchangeMatchers;

/**
 * The reactive twin of {@link ServletSecurityAutoConfiguration}, for the WebFlux-based API Gateway.
 *
 * <p>Same role mapping, same permit-all list — the Gateway validates the JWT once at the edge and
 * forwards the claims downstream, where each service re-validates rather than trusting the hop
 * (Section 2).
 */
@Configuration(proxyBeanMethods = false)
@ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.REACTIVE)
@ConditionalOnClass(ServerHttpSecurity.class)
@ConditionalOnProperty(prefix = "delivery.security", name = "enabled", havingValue = "true",
        matchIfMissing = true)
@EnableConfigurationProperties(PlatformSecurityProperties.class)
@EnableReactiveMethodSecurity
public class ReactiveSecurityAutoConfiguration {

    @Bean
    @ConditionalOnMissingBean
    public ReactiveJwtAuthenticationConverterAdapter reactiveJwtAuthenticationConverter(
            PlatformSecurityProperties properties) {
        JwtAuthenticationConverter delegate = new JwtAuthenticationConverter();
        delegate.setJwtGrantedAuthoritiesConverter(
                new KeycloakRealmRoleConverter(properties.getClientIds()));
        return new ReactiveJwtAuthenticationConverterAdapter(delegate);
    }

    /** The reactive twin of the servlet decoder — see there for why this is {@code azp}. */
    @Bean
    @ConditionalOnMissingBean(ReactiveJwtDecoder.class)
    public ReactiveJwtDecoder platformReactiveJwtDecoder(
            OAuth2ResourceServerProperties resourceServer,
            PlatformSecurityProperties properties) {
        OAuth2ResourceServerProperties.Jwt jwt = resourceServer.getJwt();

        NimbusReactiveJwtDecoder decoder =
                jwt.getJwkSetUri() != null && !jwt.getJwkSetUri().isBlank()
                        ? NimbusReactiveJwtDecoder.withJwkSetUri(jwt.getJwkSetUri()).build()
                        : NimbusReactiveJwtDecoder.withIssuerLocation(jwt.getIssuerUri()).build();

        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
                JwtValidators.createDefaultWithIssuer(jwt.getIssuerUri()),
                new AuthorizedPartyValidator(properties.getAllowedClientIds())));
        return decoder;
    }

    @Bean
    @ConditionalOnMissingBean(SecurityWebFilterChain.class)
    public SecurityWebFilterChain platformSecurityWebFilterChain(
            ServerHttpSecurity http,
            PlatformSecurityProperties properties,
            ReactiveJwtAuthenticationConverterAdapter jwtAuthenticationConverter) {

        String[] permitAll = properties.getPermitAll().toArray(String[]::new);

        return http
                .csrf(ServerHttpSecurity.CsrfSpec::disable)
                .httpBasic(ServerHttpSecurity.HttpBasicSpec::disable)
                .formLogin(ServerHttpSecurity.FormLoginSpec::disable)
                .authorizeExchange(exchange -> exchange
                        // CORS preflight must be anonymous. A browser never attaches credentials
                        // to an OPTIONS preflight, so requiring authentication here rejects it with
                        // 401 before any CORS header is written - and the browser then blocks the
                        // real request. In Flutter/Dio that surfaces as a bare "connection error"
                        // with no mention of CORS, which is a genuinely hard trail to follow.
                        .pathMatchers(HttpMethod.OPTIONS).permitAll()
                        .matchers(ServerWebExchangeMatchers.pathMatchers(permitAll)).permitAll()
                        .anyExchange().authenticated())
                .oauth2ResourceServer(oauth2 -> oauth2
                        .jwt(jwt -> jwt.jwtAuthenticationConverter(jwtAuthenticationConverter)))
                .build();
    }
}
