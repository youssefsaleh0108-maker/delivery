package com.delivery.corebanking.simulator.config;

import java.io.IOException;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * A shared API key on the bank's endpoints.
 *
 * <p>Not Keycloak. This service stands in for something outside the platform, and a real bank will
 * not validate our realm's tokens — it will hand us a credential of its own. Modelling that means
 * the connector's authentication path is exercised in dev rather than discovered in staging, which
 * is the same argument as running the simulator over real HTTP at all.
 *
 * <p>A plain filter rather than the platform's Spring Security chain, deliberately: pulling in
 * platform-security would give this service the platform's notion of identity, and the point is
 * that it does not have one.
 *
 * <p>The key is a dev constant here and comes from Vault for the connector. It protects nothing
 * real; it exists so the shape of the integration is right.
 */
@Configuration(proxyBeanMethods = false)
public class ApiKeySecurityConfiguration {

    public static final String HEADER = "X-Bank-Api-Key";

    @Bean
    public FilterRegistrationBean<ApiKeyFilter> bankApiKeyFilter(
            @Value("${delivery.corebanking.api-key:simulator-dev-key}") String expectedKey) {

        FilterRegistrationBean<ApiKeyFilter> registration =
                new FilterRegistrationBean<>(new ApiKeyFilter(expectedKey));
        // Only the bank's own contract. Actuator stays open for the container health check, and
        // /test/faults stays open so a smoke test can break the bank without holding the key.
        registration.addUrlPatterns("/api/core-banking/*");
        return registration;
    }

    public static class ApiKeyFilter extends OncePerRequestFilter {

        private final String expectedKey;

        ApiKeyFilter(String expectedKey) {
            this.expectedKey = expectedKey;
        }

        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                        FilterChain chain) throws ServletException, IOException {
            String presented = request.getHeader(HEADER);

            if (expectedKey.equals(presented)) {
                chain.doFilter(request, response);
                return;
            }

            // 401 with no detail, the way a bank would answer. A connector misconfigured with the
            // wrong key should fail loudly and permanently, not get a hint.
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.setContentType("application/json");
            response.getWriter().write("{\"error\":\"unauthorized\"}");
        }
    }
}
