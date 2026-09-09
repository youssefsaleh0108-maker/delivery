package com.delivery.tracking.client;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Which delivery company a caller is staff of, asked of Order Manager.
 *
 * <p>Order Manager owns delivery-company membership ({@code orders.provider_users}); this service
 * owns presence. The two meet at one question — "whose fleet is this caller allowed to see?" — and
 * before this client existed, order-tracking could only answer it for people it had watched carry
 * a delivery. Office staff carry nothing, so the answer for every dispatcher on the platform was
 * "no company", forever.
 *
 * <p><strong>The caller's own token is forwarded, deliberately.</strong> Not a service token: the
 * question is "which company is THIS person staff of", and forwarding their credential means Order
 * Manager decides it with its own role and membership rules. The property that matters is that a
 * provider id can never arrive from a request parameter — the only thing that can produce one is a
 * token the caller already holds.
 *
 * <p>Timeouts are short and explicit. This sits in front of a roster a console polls every few
 * seconds; a slow Order Manager must fail that poll rather than hold a request thread, because a
 * held thread here is a thread not serving rider pings.
 */
@Component
public class CarrierDirectoryClient {

    private static final Logger log = LoggerFactory.getLogger(CarrierDirectoryClient.class);

    private final RestClient orders;

    public CarrierDirectoryClient(
            RestClient.Builder builder,
            @Value("${delivery.services.order-manager:http://localhost:8101}") String orderManagerUrl,
            @Value("${delivery.clients.connect-timeout:2s}") Duration connectTimeout,
            @Value("${delivery.clients.read-timeout:5s}") Duration readTimeout) {

        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout((int) connectTimeout.toMillis());
        factory.setReadTimeout((int) readTimeout.toMillis());

        this.orders = builder.clone()
                .baseUrl(orderManagerUrl)
                .requestFactory(factory)
                .build();
    }

    /**
     * Order Manager could not be asked. Distinct from "no company" on purpose.
     *
     * <p>An outage must never be reported as "you are not a member of any delivery company": that
     * reads to a dispatcher as a provisioning fault in their own account, and the fix they would
     * then go looking for does not exist. It must also never be treated as permission — see
     * {@code CarrierScopeResolver}, which lets an existing row keep serving and refuses only when
     * there is nothing to fall back on.
     */
    public static class DirectoryUnavailableException extends RuntimeException {
        public DirectoryUnavailableException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    /**
     * The delivery company this token's bearer is staff of, or empty when they are staff of none.
     *
     * <p>Order Manager answers 404 for an account attached to no company — deliberately, because
     * whether somebody is attached to one is not worth confirming to somebody who is not. Empty is
     * that answer, and it is a fact rather than a failure: it is also how a departure is noticed.
     *
     * @param bearerToken the caller's own token, without the "Bearer " prefix
     */
    public Optional<UUID> companyFor(String bearerToken) {
        try {
            JsonNode body = orders.get()
                    .uri("/api/delivery-providers/my-company")
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + bearerToken)
                    .retrieve()
                    .body(JsonNode.class);

            String id = body == null ? null : body.path("id").asText(null);
            if (id == null || id.isBlank()) {
                // A 200 with no id is Order Manager contradicting itself. Not "no company" —
                // reporting it that way would hide a broken contract behind a plausible answer.
                throw new DirectoryUnavailableException(
                        "Order Manager returned a company with no id", null);
            }
            return Optional.of(UUID.fromString(id));

        } catch (RestClientResponseException e) {
            // 404: Order Manager has no company for this account. 403: its own role gate refused
            // the question, which is the same fact arriving in a different envelope — the caller
            // is not carrier staff. Neither is an outage, and calling either one would turn a
            // perfectly good answer into a 503 on somebody else's screen.
            if (e.getStatusCode().value() == 404 || e.getStatusCode().value() == 403) {
                return Optional.empty();
            }
            log.error("Could not resolve the caller's delivery company: {} {}",
                    e.getStatusCode(), e.getMessage());
            throw new DirectoryUnavailableException(
                    "Could not reach Order Manager to find your delivery company", e);

        } catch (IllegalArgumentException e) {
            throw new DirectoryUnavailableException(
                    "Order Manager returned a company id that is not a UUID", e);

        } catch (RestClientException e) {
            // A timeout or a connection refusal lands here, with no status to inspect.
            log.error("Could not reach Order Manager to resolve a delivery company: {}",
                    e.getMessage());
            throw new DirectoryUnavailableException(
                    "Could not reach Order Manager to find your delivery company", e);
        }
    }
}
