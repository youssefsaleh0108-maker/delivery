package com.delivery.platform.observability;

import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Contributes the correlation-ID filter appropriate to the service's web stack.
 *
 * <p>Section 10 calls this a Phase 0 requirement rather than a later add-on: with a customer action
 * rippling through a dozen independently deployed services, "why didn't this SMS arrive" is only
 * answerable if the id was there from the first commit.
 */
@AutoConfiguration
@ConditionalOnProperty(prefix = "delivery.observability", name = "correlation-id-enabled",
        havingValue = "true", matchIfMissing = true)
public class ObservabilityAutoConfiguration {

    @Configuration(proxyBeanMethods = false)
    @ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.SERVLET)
    static class ServletConfiguration {

        @Bean
        @ConditionalOnMissingBean
        public CorrelationIdFilter correlationIdFilter() {
            return new CorrelationIdFilter();
        }
    }

    @Configuration(proxyBeanMethods = false)
    @ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.REACTIVE)
    static class ReactiveConfiguration {

        @Bean
        @ConditionalOnMissingBean
        public CorrelationIdWebFilter correlationIdWebFilter() {
            return new CorrelationIdWebFilter();
        }
    }
}
