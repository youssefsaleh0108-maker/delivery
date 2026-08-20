package com.delivery.configserver;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

/**
 * The Config Server is internal-only — it is never routed through the API Gateway, and nothing a
 * user's browser can reach should ever reach it (Section 6).
 *
 * <p>Basic auth is the client-to-server credential here. Since this service is effectively
 * secrets-adjacent, staging and production additionally put it behind mTLS at the mesh/ingress
 * layer; that is deployment configuration rather than application code, so it is not represented in
 * this class. See {@code infra/README.md} for the mTLS note.
 */
@Configuration(proxyBeanMethods = false)
public class ConfigServerSecurityConfiguration {

    @Bean
    public SecurityFilterChain configServerFilterChain(HttpSecurity http) throws Exception {
        return http
                // Config clients are services posting no browser-originated forms, and the bus
                // refresh endpoint is called machine-to-machine.
                .csrf(csrf -> csrf.disable())
                .sessionManagement(session ->
                        session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/actuator/health", "/actuator/health/**", "/actuator/info")
                        .permitAll()
                        // Includes /actuator/busrefresh and every /{app}/{profile} config endpoint.
                        .anyRequest().authenticated())
                .httpBasic(Customizer.withDefaults())
                .build();
    }
}
