package com.delivery.whatsapp.client;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

import com.delivery.platform.security.CurrentUser;

/**
 * Turns a confirmed draft into a real order.
 *
 * <p>The single most important line in this whole feature is that this service does not create
 * orders itself. It asks Order Manager, which prices the basket from the catalog, applies the shop's
 * fee and minimum, publishes the event, dispatches a rider and settles the money — all the code that
 * already exists and is already tested. A WhatsApp order is an order, not a parallel kind of thing
 * that will drift out of step with the real one.
 */
public class OrderClient {

    private static final Logger log = LoggerFactory.getLogger(OrderClient.class);

    private final RestClient restClient;

    public OrderClient(RestClient restClient) {
        this.restClient = restClient;
    }

    /** Option ids only — never names or prices. The catalog prices the selection, as it always has. */
    public record Line(UUID productId, int qty, List<UUID> optionIds) {
    }

    /**
     * @param customerRef a stable, non-Keycloak reference to whoever asked over chat
     */
    public record PlaceOnBehalf(
            String customerRef,
            String customerName,
            List<Line> items,
            String deliveryAddress,
            UUID deliveryZoneId,
            String contactPhone,
            String notes,
            String paymentMethod) {
    }

    /** Only the fields the merchant needs to see back; the order itself is Order Manager's. */
    public record PlacedOrder(UUID id, String status, BigDecimal totalAmount,
                              BigDecimal deliveryFee, BigDecimal subtotal) {
    }

    /**
     * Carries the refusal's own words.
     *
     * <p>Order Manager knows things this service does not — that the shop is closed, that the basket
     * is under its minimum, that the area is not served. Replacing those with a generic failure
     * would leave the merchant staring at "could not place order" with no idea what to change.
     */
    public static class OrderRefusedException extends RuntimeException {
        private final int status;

        public OrderRefusedException(int status, String message) {
            super(message);
            this.status = status;
        }

        public int getStatus() {
            return status;
        }
    }

    public PlacedOrder place(PlaceOnBehalf request) {
        String token = CurrentUser.jwt().map(Jwt::getTokenValue).orElse(null);
        if (token == null) {
            throw new OrderRefusedException(500, "no credentials to place the order with");
        }

        try {
            PlacedOrder placed = restClient.post()
                    .uri("/api/orders/on-behalf")
                    // The merchant's own token. Order Manager derives the merchant of record from
                    // it and refuses any basket that is not their own catalog — which is what stops
                    // one shop taking orders against another's menu.
                    .header("Authorization", "Bearer " + token)
                    .body(request)
                    .retrieve()
                    .body(PlacedOrder.class);
            if (placed == null) {
                throw new OrderRefusedException(502, "the order service returned nothing");
            }
            return placed;
        } catch (RestClientResponseException e) {
            String detail = e.getResponseBodyAsString();
            log.warn("Order Manager refused a WhatsApp order: {} {}", e.getStatusCode(), detail);
            throw new OrderRefusedException(e.getStatusCode().value(),
                    detail == null || detail.isBlank() ? "the order was refused" : detail);
        } catch (OrderRefusedException e) {
            throw e;
        } catch (Exception e) {
            log.error("Could not reach Order Manager to place a WhatsApp order", e);
            throw new OrderRefusedException(502, "the order service could not be reached");
        }
    }
}
