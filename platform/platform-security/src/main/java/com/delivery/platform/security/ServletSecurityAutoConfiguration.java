package com.delivery.platform.security;

import jakarta.servlet.DispatcherType;

import org.springframework.boot.autoconfigure.condition.ConditionalOnClass;
import org.springframework.boot.autoconfigure.security.oauth2.resource.OAuth2ResourceServerProperties;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.web.SecurityFilterChain;

/**
 * Default resource-server wiring for the servlet-based domain services (Section 3).
 *
 * <p>Every service gets this without configuring anything: stateless JWT validation, realm roles
 * mapped to authorities, actuator probes open, everything else authenticated. A service that needs
 * something different just declares its own {@code SecurityFilterChain} and this backs off.
 */
@Configuration(proxyBeanMethods = false)
@ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.SERVLET)
@ConditionalOnClass(HttpSecurity.class)
@ConditionalOnProperty(prefix = "delivery.security", name = "enabled", havingValue = "true",
        matchIfMissing = true)
@EnableConfigurationProperties(PlatformSecurityProperties.class)
@EnableMethodSecurity
public class ServletSecurityAutoConfiguration {

    @Bean
    @ConditionalOnMissingBean
    public JwtAuthenticationConverter jwtAuthenticationConverter(PlatformSecurityProperties properties) {
        JwtAuthenticationConverter converter = new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(
                new KeycloakRealmRoleConverter(properties.getClientIds()));
        return converter;
    }

    /**
     * Layers the {@code azp} allow-list on top of Spring's defaults (issuer, signature, expiry).
     *
     * <p>Contributed as a {@code JwtDecoder} rather than as a validator bean because Boot only
     * applies a custom {@code OAuth2TokenValidator} if it builds the decoder itself — declaring the
     * decoder is the supported way to add one without losing the issuer check, which
     * {@code withIssuerLocation} keeps.
     */
    @Bean
    @ConditionalOnMissingBean(JwtDecoder.class)
    public JwtDecoder platformJwtDecoder(OAuth2ResourceServerProperties resourceServer,
                                         PlatformSecurityProperties properties) {
        OAuth2ResourceServerProperties.Jwt jwt = resourceServer.getJwt();

        NimbusJwtDecoder decoder = jwt.getJwkSetUri() != null && !jwt.getJwkSetUri().isBlank()
                // The realm is reached on a different address inside the cluster than the one
                // stamped into `iss`, so the keys and the issuer are configured separately.
                ? NimbusJwtDecoder.withJwkSetUri(jwt.getJwkSetUri()).build()
                : NimbusJwtDecoder.withIssuerLocation(jwt.getIssuerUri()).build();

        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
                JwtValidators.createDefaultWithIssuer(jwt.getIssuerUri()),
                new AuthorizedPartyValidator(properties.getAllowedClientIds())));
        return decoder;
    }

    @Bean
    @ConditionalOnMissingBean(SecurityFilterChain.class)
    public SecurityFilterChain platformSecurityFilterChain(
            HttpSecurity http,
            PlatformSecurityProperties properties,
            JwtAuthenticationConverter jwtAuthenticationConverter) throws Exception {

        String[] permitAll = properties.getPermitAll().toArray(String[]::new);

        return http
                // No browser session and no server-side state: clients hold the Keycloak token,
                // so CSRF and the session fixation defences have nothing to protect here.
                .csrf(csrf -> csrf.disable())
                .sessionManagement(session ->
                        session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        // CORS preflight carries no credentials - see the note in
                        // ReactiveSecurityAutoConfiguration. Browsers reach these services through
                        // the Gateway, but a service hit directly (Swagger, a debug session) needs
                        // the same allowance.
                        .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                        // The ERROR dispatch, and this is not a loosening of anything.
                        //
                        // When a request fails — a validation error, an unmapped exception —
                        // Spring re-dispatches it internally to /error to render the body. That
                        // re-dispatch goes back through this filter chain, where /error matches
                        // nothing and falls to `authenticated()`. On a permitAll endpoint reached
                        // with no token, the 400 or 500 is therefore replaced by a 401.
                        //
                        // The cost is not cosmetic. It tells the caller "you are not signed in"
                        // when the truth is "a field is missing", which is a lie that sends
                        // everybody debugging in the wrong direction — it did exactly that here,
                        // twice. Nothing is exposed by allowing it: the request already ran and
                        // failed, and this only decides who may read the error page describing it.
                        .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()
                        .requestMatchers(permitAll).permitAll()
                        .anyRequest().authenticated())
                .oauth2ResourceServer(oauth2 -> oauth2
                        .jwt(jwt -> jwt.jwtAuthenticationConverter(jwtAuthenticationConverter)))
                .httpBasic(basic -> basic.disable())
                .formLogin(form -> form.disable())
                .build();
    }
}
