package com.delivery.whatsapp.config;

import java.time.Duration;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

import com.delivery.whatsapp.client.OrderClient;
import com.delivery.whatsapp.client.ProductClient;

/**
 * The two services this one talks to.
 *
 * <p>Both are called with the merchant's own token forwarded, so the ownership rules that already
 * exist in the catalog and in Order Manager are the ones that apply. This service holds no privilege
 * of its own, which is a large part of why it can be trusted with a public webhook.
 */
@Configuration(proxyBeanMethods = false)
public class ClientConfig {

    @Bean
    public ProductClient productClient(
            RestClient.Builder builder,
            @Value("${delivery.services.product-service}") String baseUrl,
            @Value("${delivery.clients.connect-timeout:2s}") Duration connectTimeout,
            @Value("${delivery.clients.read-timeout:5s}") Duration readTimeout) {
        return new ProductClient(builder.baseUrl(baseUrl)
                .requestFactory(factory(connectTimeout, readTimeout)).build());
    }

    /**
     * A longer read timeout than the catalog lookup.
     *
     * <p>Placing an order runs the pricing, the shop's terms and the outbox write in one
     * transaction. Timing out part-way leaves the merchant unsure whether their customer is getting
     * food — the one question this feature exists to answer.
     */
    @Bean
    public OrderClient orderClient(
            RestClient.Builder builder,
            @Value("${delivery.services.order-manager}") String baseUrl,
            @Value("${delivery.clients.connect-timeout:2s}") Duration connectTimeout,
            @Value("${delivery.clients.order-read-timeout:15s}") Duration readTimeout) {
        return new OrderClient(builder.baseUrl(baseUrl)
                .requestFactory(factory(connectTimeout, readTimeout)).build());
    }

    private SimpleClientHttpRequestFactory factory(Duration connectTimeout, Duration readTimeout) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout((int) connectTimeout.toMillis());
        factory.setReadTimeout((int) readTimeout.toMillis());
        return factory;
    }
}
