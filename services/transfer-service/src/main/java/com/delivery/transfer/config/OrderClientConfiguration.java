package com.delivery.transfer.config;

import java.time.Duration;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.client.RestClientCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

import com.delivery.transfer.client.OrderManagerClient;

@Configuration(proxyBeanMethods = false)
public class OrderClientConfiguration {

    /**
     * Timeouts are short on purpose. The check sits in front of recording a payment intent, in the
     * checkout path, so a slow Order Manager must refuse and let the customer try again rather
     * than hold a request thread — nothing is written until it answers, so a refusal leaves
     * nothing half-recorded behind it.
     */
    @Bean
    public OrderManagerClient orderManagerClient(
            RestClient.Builder builder,
            @Value("${delivery.services.order-manager:http://localhost:8101}") String baseUrl,
            @Value("${delivery.clients.connect-timeout:2s}") Duration connectTimeout,
            @Value("${delivery.clients.read-timeout:5s}") Duration readTimeout) {

        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout((int) connectTimeout.toMillis());
        factory.setReadTimeout((int) readTimeout.toMillis());

        return new OrderManagerClient(builder.baseUrl(baseUrl).requestFactory(factory).build());
    }

    /** Keeps the correlation id attached to the outbound hop (Section 10). */
    @Bean
    public RestClientCustomizer correlationIdCustomizer() {
        return builder -> builder.requestInterceptor((request, body, execution) -> {
            String correlationId = org.slf4j.MDC.get("correlationId");
            if (correlationId != null) {
                request.getHeaders().add("X-Correlation-Id", correlationId);
            }
            return execution.execute(request, body);
        });
    }
}
