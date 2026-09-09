package com.delivery.transfer.client;

import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.client.RestClient;

import com.delivery.platform.security.CurrentUser;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * Asks Order Manager whether an order exists and who placed it, before this service records money
 * against it.
 *
 * <p>Neither fact can be established locally. An order id is a client-supplied UUID and the
 * transfers table is the only place it appears in this schema, so with nothing asked the first
 * caller to name an id owns the payment intent for it — including an id no order was ever placed
 * under, and including somebody else's order, whose genuine owner then cannot record their own
 * intent at all. The call is synchronous because there is no useful "record it now and reconcile
 * later" for a payment intent: an intent against an order that does not exist is not a thing to
 * repair afterwards.
 *
 * <p>The caller's own bearer token is forwarded rather than a service account's, following the
 * catalog lookup in Order Manager. It means the visibility rule Order Manager already enforces —
 * an order answers only to its customer, its merchant and its rider — is the rule that decides
 * here, instead of this service re-implementing that rule against fields it does not own.
 */
public class OrderManagerClient {

    private static final Logger log = LoggerFactory.getLogger(OrderManagerClient.class);

    private final RestClient restClient;

    public OrderManagerClient(RestClient restClient) {
        this.restClient = restClient;
    }

    /**
     * @throws OrderUnavailableException when the order does not exist, is not the caller's, or
     *         Order Manager cannot be reached — all of which must stop the transfer rather than
     *         let it record an obligation nobody can settle
     */
    public OrderSummary fetch(UUID orderId) {
        String token = CurrentUser.jwt()
                .map(Jwt::getTokenValue)
                .orElseThrow(() -> new IllegalStateException(
                        "No bearer token to forward - is this call outside a request?"));

        try {
            OrderSummary order = restClient.get()
                    .uri("/api/orders/{id}", orderId)
                    .header("Authorization", "Bearer " + token)
                    .retrieve()
                    .onStatus(HttpStatusCode::isError, (request, response) -> {
                        // Order Manager answers 404 for an order the caller cannot see as well as
                        // for one that was never placed, on purpose — a 403 would confirm the id
                        // exists. This service must not undo that by naming which it was.
                        if (response.getStatusCode().value() == HttpStatus.NOT_FOUND.value()) {
                            throw new OrderUnavailableException(
                                    "That order does not exist, or is not yours");
                        }
                        throw new OrderUnavailableException(
                                "The order could not be confirmed; please try again");
                    })
                    .body(OrderSummary.class);

            if (order == null || order.customerId() == null) {
                throw new OrderUnavailableException(
                        "The order could not be confirmed; please try again");
            }
            return order;
        } catch (OrderUnavailableException e) {
            throw e;
        } catch (Exception e) {
            log.error("Could not reach Order Manager to confirm order {}", orderId, e);
            throw new OrderUnavailableException(
                    "The order could not be confirmed; please try again");
        }
    }

    /**
     * Only the fields an ownership check needs. Order Manager's response carries a whole order;
     * binding the rest here would make this service break every time that payload grows a field.
     */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record OrderSummary(UUID id, String customerId, String status) {
    }

    public static class OrderUnavailableException extends RuntimeException {
        public OrderUnavailableException(String message) {
            super(message);
        }
    }
}
