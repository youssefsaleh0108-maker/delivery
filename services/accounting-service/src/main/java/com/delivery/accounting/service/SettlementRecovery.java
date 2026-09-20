package com.delivery.accounting.service;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.event.OrderEventListener;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

/**
 * Finds delivered orders the ledger has never seen, and settles them (RECON-04).
 *
 * <p><strong>Why it has to ask another service.</strong> A settlement lost on the bus leaves no
 * trace here at all: no legs, no float row, nothing for a reconciliation view to list, because every
 * one of them reads legs that exist. The only record that the order was delivered belongs to Order
 * Manager, so the check is a comparison between its delivered orders and this ledger. Dev has
 * carried two such orders since 2026-09-08 — 9576be97 and dcb4f889, discounted to 0.00 by a code and
 * refused by the settlement rules of that day — with the shop owed 13.11 and the delivery company
 * 4.72 and nobody able to see it.
 *
 * <p><strong>Settled through the same rules, never a second copy of them.</strong> The order is
 * shaped back into the event the listener would have received and handed to
 * {@link OrderEventListener#settleDelivered}: the same waivers, the same clamps, the same cash
 * holder, the same points. Idempotent twice over — settlement does nothing for an order that
 * already has legs, and the float's own guard does nothing for cash already booked — so pressing
 * the button twice is safe, and so is pressing it on an order that settled a second ago.
 */
@Service
public class SettlementRecovery {

    private static final Logger log = LoggerFactory.getLogger(SettlementRecovery.class);

    /**
     * The most delivered orders one check compares against the ledger.
     *
     * <p>Every one of them, up to this: a settlement that went missing a month ago is not in this
     * week's hundred, and a check that looked only at the newest orders answered "nothing missing"
     * while two of them sat there. The cap is a bound on one request, and a scan that hits it says
     * so rather than reporting a clean ledger.
     */
    public static final int MAX_ORDERS = 5_000;

    /** How many order ids one ledger query asks about. */
    private static final int LEDGER_BATCH = 200;

    private final OrderManagerOrdersClient orderManager;
    private final AccountingTransactionRepository transactions;
    private final OrderEventListener settlements;
    private final SettlementFailures failures;
    private final ObjectMapper objectMapper;
    private final String unmappedAccount;

    public SettlementRecovery(OrderManagerOrdersClient orderManager,
                              AccountingTransactionRepository transactions,
                              OrderEventListener settlements,
                              SettlementFailures failures,
                              ObjectMapper objectMapper,
                              @Value("${delivery.accounting.unmapped-account:ACC-UNMAPPED}")
                              String unmappedAccount) {
        this.orderManager = orderManager;
        this.transactions = transactions;
        this.settlements = settlements;
        this.failures = failures;
        this.objectMapper = objectMapper;
        this.unmappedAccount = unmappedAccount;
    }

    /**
     * One delivered order with nothing in the ledger.
     *
     * @param settleable whether the money was collected, and so whether settling it now is right
     * @param reason     why it cannot be settled yet, when it cannot
     */
    public record Missing(UUID orderId, String status, String paymentMethod, String paymentStatus,
                          String totalAmount, String deliveredAt, boolean settleable,
                          String reason) {
    }

    /**
     * What the check looked at and what it found.
     *
     * @param scanned  how many delivered orders were compared against the ledger
     * @param complete whether that was all of them. False means the scan stopped at the cap, and
     *                 an older order it never reached could still be missing
     */
    public record Check(int scanned, boolean complete, List<Missing> missing) {
    }

    /**
     * Delivered orders with no legs at all.
     *
     * <p><strong>"No ledger rows" means exactly that.</strong> The only thing consulted is
     * {@code transactions}: an order is settled when it has legs, and nothing else — not a points
     * row, not a float row, not a failure record — counts as evidence that it was. The two orders
     * stuck on dev have points from the run that failed and no legs, which is precisely the state
     * this has to find.
     *
     * <p>Read-only and safe to run at any time: it writes nothing and settles nothing. An order
     * whose money was never collected is listed too, with the reason — it is not the platform's to
     * settle, and an operator chasing an unpaid card order is a better outcome than silence.
     */
    public Check unsettledDeliveries(String bearerToken, int limit) {
        OrderManagerOrdersClient.Delivered delivered = orderManager.delivered(bearerToken,
                Math.max(1, Math.min(limit, MAX_ORDERS)));

        List<UUID> ids = new ArrayList<>(delivered.orders().size());
        for (JsonNode order : delivered.orders()) {
            UUID id = idOf(order);
            if (id != null) {
                ids.add(id);
            }
        }
        Set<UUID> settled = new HashSet<>();
        // In batches: one IN clause of two thousand ids is a query nobody planned for.
        for (int from = 0; from < ids.size(); from += LEDGER_BATCH) {
            List<UUID> batch = ids.subList(from, Math.min(from + LEDGER_BATCH, ids.size()));
            for (AccountingTransaction leg : transactions.findByOrderIdIn(batch)) {
                settled.add(leg.getOrderId());
            }
        }

        List<Missing> missing = new ArrayList<>();
        for (JsonNode order : delivered.orders()) {
            UUID id = idOf(order);
            if (id == null || settled.contains(id)) {
                continue;
            }
            String paymentStatus = order.path("paymentStatus").asText(null);
            boolean collected = paymentStatus == null
                    || "COLLECTED".equals(paymentStatus) || "CAPTURED".equals(paymentStatus);
            missing.add(new Missing(id, order.path("status").asText(null),
                    order.path("paymentMethod").asText(null), paymentStatus,
                    order.path("totalAmount").asText(null),
                    order.path("deliveredAt").asText(null), collected,
                    collected ? null : "The money was never collected: the payment is "
                            + paymentStatus + "."));
        }
        log.info("{} of {} delivered orders have no ledger rows (scan complete: {})",
                missing.size(), delivered.orders().size(), delivered.complete());
        return new Check(delivered.orders().size(), delivered.complete(), missing);
    }

    /** What settling one order by hand did. */
    public record Settled(UUID orderId, boolean settled, int legs, String reason) {
    }

    /**
     * Settles one delivered order from Order Manager's record of it.
     *
     * <p><strong>Not one transaction, and that is the fix.</strong> Re-driving a settlement means
     * completing what is missing and leaving alone what is already there, and the pieces are not
     * all in the ledger: the two stuck orders on dev had their loyalty points awarded by the run
     * that failed in September and only their legs missing. Wrapped in one transaction, the
     * tolerated duplicate on those points aborted the whole re-drive — Postgres refuses every
     * further statement on a transaction a failure has aborted — and the order stayed unsettled
     * with a 500 for an answer. Each step now owns its own transaction, exactly as it does when the
     * listener drives it, and each is idempotent on its own: the legs on {@code existsByOrderId},
     * the cash float on its collection guard, the points and the rider's row on an existence check
     * before the insert and their unique indexes behind it.
     *
     * @param by the operator, for the audit trail on the failure it closes
     * @throws IllegalArgumentException the order is not one this service may settle: unknown, not
     *                                  delivered, or already in the ledger
     */
    public Settled settle(String bearerToken, UUID orderId, String by) {
        if (transactions.existsByOrderId(orderId)) {
            // Already settled — by a redelivery, or by somebody pressing the same button first.
            failures.resolve(orderId, by, "The order was already settled.");
            return new Settled(orderId, false, 0, "That order is already in the ledger.");
        }

        JsonNode order = orderManager.order(bearerToken, orderId);
        if (order == null || order.isEmpty()) {
            throw new IllegalArgumentException("Order Manager has no order " + orderId);
        }
        String status = order.path("status").asText(null);
        if (!"DELIVERED".equals(status)) {
            throw new IllegalArgumentException(
                    "Only a delivered order can be settled; that one is " + status);
        }

        OrderEventListener.Outcome outcome =
                settlements.settleDelivered(asDeliveredEvent(order), "recovery-" + orderId);
        if (!outcome.settled()) {
            failures.record(orderId, "order.delivered", outcome.reason(),
                    order.toString(), "recovery-" + orderId);
            return new Settled(orderId, false, 0, outcome.reason());
        }

        int legs = transactions.findByOrderIdOrderByCreatedAt(orderId).size();
        failures.resolve(orderId, by, "Settled by hand from Order Manager's record: " + legs
                + " legs.");
        log.info("Order {} settled by {} from Order Manager's record: {} legs", orderId, by, legs);
        return new Settled(orderId, true, legs, null);
    }

    /**
     * Shapes Order Manager's order into the {@code order.delivered} event it once published.
     *
     * <p>Field for field the same names, because the listener reads that shape and there must not be
     * a second reading of it. Two differences are worth stating:
     *
     * <ul>
     *   <li>the wrap fee lives inside {@code gift} on the REST shape and beside the fee on the
     *       event, so it is lifted out;</li>
     *   <li>{@code deliveryProviderAccount} is deliberately not on the REST shape — knowing who
     *       delivered an order is reasonable, knowing where they bank is not. What it decides here
     *       is only whether the fee is a company's or the rider's own, which {@code
     *       deliveryProviderId} answers, so the company's leg is booked to the unmapped account:
     *       the amount, the counterparty and the statement are right, and the account reads as the
     *       placeholder it is. Nothing posts it anywhere, because no bank is deployed.</li>
     * </ul>
     */
    ObjectNode asDeliveredEvent(JsonNode order) {
        ObjectNode event = objectMapper.createObjectNode();
        event.put("orderId", order.path("id").asText());
        for (String field : List.of("kind", "customerId", "merchantId", "riderId", "status",
                "totalAmount", "subtotal", "deliveryFee", "expressSurcharge", "deliveryFeeWaived",
                "merchantFeeWaived", "carrierFeeWaived", "discountAmount", "promoCode", "storeId",
                "storeName", "checkoutId", "paymentMethod", "paymentStatus", "deliveryAddress",
                "fulfilment", "serviceCategory", "deliveryProviderId", "deliveredAt", "placedAt")) {
            JsonNode value = order.get(field);
            if (value != null && !value.isNull()) {
                event.set(field, value);
            }
        }
        JsonNode gift = order.path("gift");
        if (gift.isObject() && gift.path("wrapFee").isNumber()) {
            event.set("giftWrapFee", gift.path("wrapFee"));
        }
        if (!order.path("deliveryProviderId").isNull()
                && !order.path("deliveryProviderId").asText("").isBlank()) {
            event.put("deliveryProviderAccount", unmappedAccount);
        }
        return event;
    }

    private static UUID idOf(JsonNode order) {
        try {
            String id = order.path("id").asText(null);
            return id == null ? null : UUID.fromString(id);
        } catch (IllegalArgumentException e) {
            return null;
        }
    }
}
