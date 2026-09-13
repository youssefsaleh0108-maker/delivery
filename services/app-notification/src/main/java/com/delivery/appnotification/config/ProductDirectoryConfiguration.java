package com.delivery.appnotification.config;

import java.time.Duration;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

import com.delivery.appnotification.client.ProductDirectory;

/**
 * The HTTP client behind {@link ProductDirectory}.
 *
 * <p>Timeouts are short and explicit because every caller of the directory is a person waiting on a
 * chat screen: a Product Service that hangs must become a quick 503 the app can retry, not a request
 * thread held for the JDK's default of forever. {@code PRODUCT_SERVICE_URL} is already in the
 * {@code platform-common} config map this deployment reads.
 */
@Configuration(proxyBeanMethods = false)
public class ProductDirectoryConfiguration {

    @Bean
    public ProductDirectory productDirectory(
            @Value("${delivery.clients.product-service.base-url:http://localhost:8103}") String baseUrl,
            @Value("${delivery.clients.product-service.connect-timeout:2s}") Duration connectTimeout,
            @Value("${delivery.clients.product-service.read-timeout:5s}") Duration readTimeout) {

        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout((int) connectTimeout.toMillis());
        factory.setReadTimeout((int) readTimeout.toMillis());

        // The static builder rather than Boot's injected RestClient.Builder: this service has never
        // made an outbound HTTP call, and its test suite loads no Spring context, so a missing
        // auto-configured builder would only surface as a crash-loop on deploy.
        return new ProductDirectory(RestClient.builder()
                .baseUrl(baseUrl)
                .requestFactory(factory)
                .build());
    }
}
