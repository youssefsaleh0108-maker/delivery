package com.delivery.appnotification.api;

import java.util.Arrays;
import java.util.List;
import java.util.Map;

import org.springframework.aop.framework.ProxyFactory;
import org.springframework.security.authorization.method.AuthorizationManagerBeforeMethodInterceptor;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.oauth2.server.resource.web.BearerTokenAuthenticationEntryPoint;
import org.springframework.security.oauth2.server.resource.web.access.BearerTokenAccessDeniedHandler;
import org.springframework.security.web.access.ExceptionTranslationFilter;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

/**
 * A controller behind the real {@code @PreAuthorize} interceptor and the real refusal filter, so an
 * access test sees the 401 and 403 a client would.
 *
 * <p>Needed because the whole guard on these endpoints is an annotation, which a plain standalone
 * MockMvc never evaluates — a test built that way would pass with the annotation deleted. The same
 * construction product-service's {@code StoreVerifiedLocalAccessTest} uses.
 */
final class SecuredMvc {

    private SecuredMvc() {
    }

    static MockMvc of(Object controller) {
        ProxyFactory factory = new ProxyFactory(controller);
        factory.setProxyTargetClass(true);
        factory.addAdvisor(AuthorizationManagerBeforeMethodInterceptor.preAuthorize());

        ExceptionTranslationFilter refusals =
                new ExceptionTranslationFilter(new BearerTokenAuthenticationEntryPoint());
        refusals.setAccessDeniedHandler(new BearerTokenAccessDeniedHandler());

        return MockMvcBuilders.standaloneSetup(factory.getProxy())
                .setControllerAdvice(new ChatExceptionHandler())
                .addFilters(refusals)
                .build();
    }

    static void signedInAs(String subject, String... roles) {
        signedInAs(subject, Map.of(), roles);
    }

    static void signedInAs(String subject, Map<String, Object> claims, String... roles) {
        Jwt.Builder jwt = Jwt.withTokenValue("token").header("alg", "none").subject(subject);
        claims.forEach(jwt::claim);
        List<GrantedAuthority> authorities = Arrays.stream(roles)
                .<GrantedAuthority>map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .toList();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(jwt.build(), authorities));
    }
}
