package com.delivery.accounting.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Which delivery company the caller is staff of, asked of Order Manager.
 *
 * <p>This exists because a carrier's identity has two forms and this service only ever sees one of
 * them. Every {@code PROVIDER_CREDIT} leg is attributed with the {@code deliveryProviderId} carried
 * on the order event — an Order Manager row id. A carrier signing in to read their own statement
 * presents a Keycloak token whose subject is their staff account. The two are different namespaces,
 * and looking a carrier up by their subject matches nothing.
 *
 * <p><strong>That failure was silent, which is why this class is worth its weight.</strong> Asking
 * for legs by the wrong id returns no rows, the lines sum to zero, the balance check passes because
 * zero really does equal zero, and the statement renders as a legitimate quiet month — while the
 * company's money sits in the ledger under an id nobody looked for. A delivery company was being
 * told it was owed nothing.
 *
 * <p>The mapping lives in Order Manager ({@code orders.provider_users}) and is not this service's to
 * duplicate: a second copy would drift the first time somebody joins or leaves a fleet. So this asks
 * the service that owns it, through the endpoint that already answers the question.
 *
 * <p><strong>The caller's own token is forwarded, deliberately.</strong> Not a service token: the
 * question being asked is "which company is THIS person staff of", and forwarding their credential
 * means Order Manager decides that with its own {@code hasRole('CARRIER')} check and its own
 * membership rule. This service never has to be trusted with the answer, and — the property that
 * matters — a provider id can never arrive from a request parameter, because the only thing that
 * can produce one is a token the caller already holds.
 */
@Component
public class CarrierCompanyClient {

    private static final Logger log = LoggerFactory.getLogger(CarrierCompanyClient.class);

    private final RestClient orders;

    public CarrierCompanyClient(
            RestClient.Builder builder,
            @Value("${delivery.services.order-manager:http://localhost:8101}") String orderManagerUrl) {
        this.orders = builder.clone().baseUrl(orderManagerUrl).build();
    }

    /** Thrown when the caller holds CARRIER but belongs to no company. */
    public static class NoCompanyException extends RuntimeException {
        public NoCompanyException(String message) {
            super(message);
        }
    }

    /**
     * The provider id for the bearer of this token.
     *
     * <p>Order Manager answers 404 for an account that is not carrier staff — deliberately, because
     * whether somebody is attached to a company is not worth confirming to somebody who is not. That
     * becomes a {@link NoCompanyException} here so the caller can say something true instead of
     * rendering an empty statement, which is the whole failure this replaces.
     *
     * @param bearerToken the caller's own Authorization header value, without the "Bearer " prefix
     */
    public String companyIdFor(String bearerToken) {
        try {
            JsonNode body = orders.get()
                    .uri("/api/delivery-providers/my-company")
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + bearerToken)
                    .retrieve()
                    .body(JsonNode.class);

            String id = body == null ? null : body.path("id").asText(null);
            if (id == null || id.isBlank()) {
                throw new NoCompanyException(
                        "Order Manager returned a company with no id");
            }
            return id;

        } catch (RestClientResponseException e) {
            if (e.getStatusCode().value() == 404) {
                throw new NoCompanyException(
                        "This account is not staff of any delivery company");
            }
            // Anything else is an outage or a misconfiguration, and must NOT be turned into
            // "you have no company" — that reads to a carrier as "you are owed nothing".
            log.error("Could not resolve the caller's delivery company: {} {}",
                    e.getStatusCode(), e.getMessage());
            throw new IllegalStateException(
                    "Could not reach Order Manager to find your delivery company", e);
        }
    }
}
