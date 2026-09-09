package com.delivery.platform.observability;

import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.web.client.RestClientCustomizer;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;

/**
 * Contributes the correlation-ID filter appropriate to the service's web stack.
 *
 * <p>Section 10 calls this a Phase 0 requirement rather than a later add-on: with a customer action
 * rippling through a dozen independently deployed services, "why didn't this SMS arrive" is only
 * answerable if the id was there from the first commit.
 */
@AutoConfiguration
@EnableConfigurationProperties(OutboundCallDefaults.class)
public class ObservabilityAutoConfiguration {

    /**
     * A deadline on every cross-service call, whether or not whoever wrote the client remembered.
     *
     * <p>Spring's default request factory has NO connect or read timeout, so a dependency that
     * accepts the connection and then never answers holds the calling thread indefinitely — and
     * a caller that hangs never throws, so the careful fallback most of these clients have around
     * their call is unreachable. Six clients across three services were built this way, including
     * the account directory that the accounting ledger consumer calls two or three times per
     * settlement on its single deliberately-serial thread: one unanswered call there stops every
     * settlement on the platform, silently and for as long as the far end stays quiet.
     *
     * <p>Applied to the injected {@code RestClient.Builder} rather than to each client, because
     * the failure was not one client getting it wrong — it was that getting it right was
     * something each new client had to remember. A client with a genuine reason to wait longer
     * sets its own request factory and this stops applying to it.
     */
    @Bean
    @ConditionalOnMissingBean(name = "platformOutboundTimeouts")
    public RestClientCustomizer platformOutboundTimeouts(OutboundCallDefaults defaults) {
        return builder -> {
            SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
            factory.setConnectTimeout((int) defaults.connectTimeout().toMillis());
            factory.setReadTimeout((int) defaults.readTimeout().toMillis());
            builder.requestFactory(factory);
        };
    }

    @Configuration(proxyBeanMethods = false)
    @ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.SERVLET)
    @ConditionalOnProperty(prefix = "delivery.observability", name = "correlation-id-enabled",
            havingValue = "true", matchIfMissing = true)
    static class ServletConfiguration {

        @Bean
        @ConditionalOnMissingBean
        public CorrelationIdFilter correlationIdFilter() {
            return new CorrelationIdFilter();
        }
    }

    @Configuration(proxyBeanMethods = false)
    @ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.REACTIVE)
    @ConditionalOnProperty(prefix = "delivery.observability", name = "correlation-id-enabled",
            havingValue = "true", matchIfMissing = true)
    static class ReactiveConfiguration {

        @Bean
        @ConditionalOnMissingBean
        public CorrelationIdWebFilter correlationIdWebFilter() {
            return new CorrelationIdWebFilter();
        }
    }
}
