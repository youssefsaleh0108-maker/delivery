package com.delivery.accounting.service;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Order Manager's record of an order, read for a settlement that never happened (RECON-04).
 *
 * <p>The ledger cannot tell that an order is missing from it: every reconciliation view reads legs
 * that exist, and a settlement lost on the bus leaves none. Only the service that owns the orders
 * knows an order was delivered, so that is who is asked.
 *
 * <p><strong>With the operator's own token.</strong> The Back Office is already allowed to read
 * every order, and forwarding their token means Order Manager decides that, as it does for the
 * payroll reads ({@link OrderManagerDeliveriesClient}) — rather than this service holding a
 * standing credential that can read every order on the platform unattended.
 */
@Component
public class OrderManagerOrdersClient {

    private static final Logger log = LoggerFactory.getLogger(OrderManagerOrdersClient.class);

    /** How many orders one page asks for. Order Manager's own maximum page is larger than this. */
    private static final int PAGE = 100;

    private final RestClient orders;

    @Autowired
    public OrderManagerOrdersClient(
            RestClient.Builder builder,
            @Value("${delivery.services.order-manager:http://localhost:8101}") String orderManagerUrl,
            @Value("${delivery.accounting.recovery.timeout:10s}") Duration timeout) {
        this(builder.clone().requestFactory(requestFactory(timeout)), orderManagerUrl);
    }

    OrderManagerOrdersClient(RestClient.Builder builder, String orderManagerUrl) {
        this.orders = builder.clone().baseUrl(orderManagerUrl).build();
    }

    private static SimpleClientHttpRequestFactory requestFactory(Duration timeout) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(Math.min(3, Math.max(1, timeout.toSeconds()))));
        factory.setReadTimeout(timeout);
        return factory;
    }

    /** Order Manager could not be asked. Never confused with "it answered, and there are none". */
    public static class UnavailableException extends RuntimeException {
        public UnavailableException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    /**
     * The most recently delivered orders, newest first, as Order Manager has them.
     *
     * <p>Paged until {@code limit} is reached or the pages run out. Newest first because a
     * settlement that went missing is found by looking back from now, and an operator working a
     * list wants this week before last year.
     */
    public List<JsonNode> recentlyDelivered(String bearerToken, int limit) {
        List<JsonNode> found = new ArrayList<>();
        for (int page = 0; found.size() < limit; page++) {
            final int number = page;
            JsonNode body = get(bearerToken, uri -> uri.path("/api/orders")
                    .queryParam("status", "DELIVERED")
                    .queryParam("page", number)
                    .queryParam("size", Math.min(PAGE, limit))
                    .queryParam("sort", "placedAt,desc")
                    .build());
            JsonNode content = body == null ? null : body.path("content");
            if (content == null || !content.isArray() || content.isEmpty()) {
                break;
            }
            content.forEach(found::add);
            int totalPages = body.path("totalPages").asInt(0);
            if (number + 1 >= totalPages) {
                break;
            }
        }
        return found.size() > limit ? found.subList(0, limit) : found;
    }

    /** One order as Order Manager has it, or null when it does not have it. */
    public JsonNode order(String bearerToken, UUID orderId) {
        return get(bearerToken, uri -> uri.path("/api/orders/" + orderId).build());
    }

    private JsonNode get(String bearerToken,
                         java.util.function.Function<org.springframework.web.util.UriBuilder,
                                 java.net.URI> uri) {
        try {
            return orders.get()
                    .uri(uri::apply)
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + bearerToken)
                    .retrieve()
                    .body(JsonNode.class);
        } catch (RestClientResponseException e) {
            if (e.getStatusCode().value() == 404) {
                return null;
            }
            log.warn("Order Manager refused the read: {} {}", e.getStatusCode(), e.getMessage());
            throw new UnavailableException(
                    "Order Manager answered " + e.getStatusCode().value(), e);
        } catch (RestClientException e) {
            log.warn("Order Manager could not be reached", e);
            throw new UnavailableException("Order Manager could not be reached", e);
        }
    }
}
