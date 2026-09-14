package com.delivery.appnotification.client;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import com.delivery.appnotification.service.RoomExceptions.OrderUnavailableException;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * One order as Order Manager shows it to the caller: what a shop thread must know before it may be
 * labelled with that order.
 *
 * <p><strong>The order read every app already makes, with the caller's own token.</strong>
 * {@code GET /api/orders/{id}} is sent the bearer exactly as {@link DeliveredAreas} sends it. Order
 * Manager answers that read only for the order's customer, the merchant it was placed with and its
 * rider, and answers everybody else 404 — so nothing learnt here is about an order the caller could
 * not already open in their own app. It carries every fact a link is decided on (the shop, the
 * customer, the kind, the status, when the order was placed, when its work was promised and when it
 * was delivered or cancelled, the name on the shop's card), which is why no narrower endpoint was
 * added: a second read of the same row would be a second visibility rule to keep in step with the
 * first.
 *
 * <p><strong>The customer's user id read here goes no further.</strong> It decides which thread an
 * order belongs to; no view of a thread carries it, so a merchant's app never receives it from chat.
 *
 * <p><strong>Never cached.</strong> Opening a chat is a tap, not a message, and the answer is checked
 * against the order's current status. A remembered answer would be a second place access is decided,
 * and a refusal can never be remembered as a success when nothing is remembered.
 *
 * <p><strong>Fails closed.</strong> 404, 403 and 400 mean "no such order for this caller" and read as
 * empty. Everything else — unreachable, slower than the timeout, a 5xx, a token Order Manager rejects,
 * an answer without the facts a link is decided on — is {@link OrderUnavailableException}, never a
 * guess in either direction.
 */
public class OrderReferences {

    private static final Logger log = LoggerFactory.getLogger(OrderReferences.class);

    private static final String UNAVAILABLE = "Orders cannot be checked right now";

    private final RestClient rest;

    public OrderReferences(RestClient rest) {
        this.rest = rest;
    }

    /**
     * The order, if Order Manager shows it to the caller. Empty when it does not exist or is not
     * theirs to see, which Order Manager deliberately does not tell apart.
     *
     * @throws OrderUnavailableException when Order Manager cannot say
     */
    public Optional<OrderReference> visibleToCaller(UUID orderId) {
        OrderReference order;
        try {
            order = rest.get()
                    .uri("/api/orders/{id}", orderId)
                    .header(HttpHeaders.AUTHORIZATION, ProductDirectory.bearer())
                    .retrieve()
                    .body(OrderReference.class);
        } catch (HttpClientErrorException e) {
            int status = e.getStatusCode().value();
            if (status == 404 || status == 403 || status == 400) {
                return Optional.empty();
            }
            log.warn("Order Manager refused an order read ({})", status);
            throw new OrderUnavailableException(UNAVAILABLE, e);
        } catch (RestClientException e) {
            log.warn("Could not read an order from Order Manager", e);
            throw new OrderUnavailableException(UNAVAILABLE, e);
        }
        if (order == null || !orderId.equals(order.id()) || order.customerId() == null
                || order.kind() == null || order.status() == null || order.placedAt() == null) {
            log.warn("Order Manager's answer for an order lacked what a chat link is decided on");
            throw new OrderUnavailableException(UNAVAILABLE, null);
        }
        return Optional.of(order);
    }

    /**
     * Only the fields a chat link needs from Order Manager's {@code OrderResponse}.
     *
     * @param storeId             the shop it was placed with; null for an errand, which has none
     * @param storeName           the shop's name when the order was placed
     * @param customerId          who placed it: decides the thread, and is never shown to a shop
     * @param kind                CATALOG, SERVICE, ... as Order Manager spells it
     * @param status              PLACED ... DELIVERED or CANCELLED, as Order Manager spells it
     * @param placedAt            when it was placed, which Order Manager records on every order
     * @param estimatedReadyAt    when a service order's work was promised: its acceptance plus its
     *                            longest turnaround. Null until it is accepted, and on other kinds
     * @param customerDisplayName the name the shop's card shows (a first name and an initial), or null
     */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record OrderReference(UUID id,
                                 UUID storeId,
                                 String storeName,
                                 String customerId,
                                 String kind,
                                 String status,
                                 Instant placedAt,
                                 Instant estimatedReadyAt,
                                 Instant deliveredAt,
                                 Instant cancelledAt,
                                 String customerDisplayName) {

        private static final String DELIVERED = "DELIVERED";
        private static final String CANCELLED = "CANCELLED";

        /** Delivered (collected, for a pickup) or cancelled: nothing more will happen to it. */
        public boolean hasEnded() {
            return DELIVERED.equals(status) || CANCELLED.equals(status);
        }

        /** When it ended; null while it is open, and null if Order Manager recorded no time. */
        public Instant endedAt() {
            if (DELIVERED.equals(status)) {
                return deliveredAt;
            }
            if (CANCELLED.equals(status)) {
                return cancelledAt;
            }
            return null;
        }

        /**
         * When the order was due: when its work was promised, or when it was placed if nothing was — a
         * goods order, or a service order its shop has not accepted yet. Never before it was placed.
         *
         * <p>Once the shop has accepted, this is not the shop's to move. Order Manager fixes the
         * promise at acceptance, from the turnaround the customer was shown when they ordered, and
         * marking the order ready or delivered — or never doing so — changes neither time. Before
         * acceptance the customer can still cancel.
         */
        public Instant dueAt() {
            return estimatedReadyAt != null && estimatedReadyAt.isAfter(placedAt) ? estimatedReadyAt : placedAt;
        }
    }
}
