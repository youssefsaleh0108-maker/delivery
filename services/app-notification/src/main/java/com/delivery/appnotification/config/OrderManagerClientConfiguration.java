package com.delivery.appnotification.config;

import java.time.Duration;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

import com.delivery.appnotification.client.DeliveredAreas;
import com.delivery.appnotification.client.OrderReferences;

/**
 * The HTTP clients behind {@link DeliveredAreas} and {@link OrderReferences}.
 *
 * <p>Built the way {@link ProductDirectoryConfiguration} builds Product Service's, for the same
 * reasons: short explicit timeouts, because the caller is a neighbour waiting on a send button, and
 * the static {@code RestClient.builder()}, because this service's test suite loads no Spring context
 * and a missing auto-configured builder would only surface as a crash-loop on deploy.
 * {@code ORDER_MANAGER_URL} is already in the {@code platform-common} config map this deployment
 * reads.
 *
 * <p>Both talk to the same Order Manager, with the same timeouts and the caller's own token, so both
 * are built by one method from one set of properties.
 */
@Configuration(proxyBeanMethods = false)
public class OrderManagerClientConfiguration {

    @Bean
    public DeliveredAreas deliveredAreas(
            @Value("${delivery.clients.order-manager.base-url:http://localhost:8101}") String baseUrl,
            @Value("${delivery.clients.order-manager.connect-timeout:2s}") Duration connectTimeout,
            @Value("${delivery.clients.order-manager.read-timeout:5s}") Duration readTimeout,
            @Value("${delivery.clients.order-manager.proof-cache-ttl:2m}") Duration cacheTtl) {
        return new DeliveredAreas(orderManager(baseUrl, connectTimeout, readTimeout), cacheTtl);
    }

    @Bean
    public OrderReferences orderReferences(
            @Value("${delivery.clients.order-manager.base-url:http://localhost:8101}") String baseUrl,
            @Value("${delivery.clients.order-manager.connect-timeout:2s}") Duration connectTimeout,
            @Value("${delivery.clients.order-manager.read-timeout:5s}") Duration readTimeout) {
        return new OrderReferences(orderManager(baseUrl, connectTimeout, readTimeout));
    }

    private static RestClient orderManager(String baseUrl, Duration connectTimeout, Duration readTimeout) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout((int) connectTimeout.toMillis());
        factory.setReadTimeout((int) readTimeout.toMillis());

        return RestClient.builder()
                .baseUrl(baseUrl)
                .requestFactory(factory)
                .build();
    }
}
