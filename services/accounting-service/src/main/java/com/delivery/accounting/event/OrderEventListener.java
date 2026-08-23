package com.delivery.accounting.event;

import java.math.BigDecimal;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Component;

import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.service.AccountDirectory;
import com.delivery.accounting.service.PointsService;
import com.delivery.accounting.service.SettlementService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Starts a settlement when an order is delivered.
 *
 * <p>Driven off the outbox-backed bus, not called by Order Manager. Section 10 requires the bank to
 * be an asynchronous saga so a slow bank never holds up fulfilment — consuming the same
 * {@code order.delivered} event the notification layer consumes makes that a property of the
 * architecture rather than a promise about how someone calls this service.
 *
 * <p>Only {@code order.delivered} settles. A cancelled order has nothing to unwind, because nothing
 * was collected — see {@link SettlementService} for why settlement is at delivery rather than
 * checkout.
 */
@Component
public class OrderEventListener {

    private static final Logger log = LoggerFactory.getLogger(OrderEventListener.class);

    private final SettlementService settlements;
    private final AccountDirectory accounts;
    private final PointsService points;
    private final ObjectMapper objectMapper;

    public OrderEventListener(SettlementService settlements, AccountDirectory accounts,
                              PointsService points, ObjectMapper objectMapper) {
        this.settlements = settlements;
        this.accounts = accounts;
        this.points = points;
        this.objectMapper = objectMapper;
    }

    /** Payment states in which the money has genuinely moved and settlement may proceed. */
    private static final java.util.Set<String> SETTLEABLE =
            java.util.Set.of("COLLECTED", "CAPTURED");

    @RabbitListener(queues = "${delivery.accounting.order-events-queue:accounting.order-events}")
    public void onOrderEvent(String payload,
                             @Header(name = "eventType", required = false) String headerEventType,
                             @Header(name = "amqp_receivedRoutingKey", required = false) String routingKey,
                             @Header(name = "amqp_correlationId", required = false) String correlationId) {

        String eventType = headerEventType != null ? headerEventType : routingKey;
        if (!"order.delivered".equals(eventType)) {
            return;
        }

        if (correlationId != null) {
            MDC.put("correlationId", correlationId);
        }

        try {
            JsonNode event = objectMapper.readTree(payload);

            UUID orderId = UUID.fromString(event.path("orderId").asText());
            String customerId = event.path("customerId").asText(null);
            String merchantId = event.path("merchantId").asText(null);
            String riderId = event.path("riderId").asText(null);
            JsonNode total = event.path("totalAmount");

            // Absent on events published before Butler existed; those were all baskets from shops.
            String kind = event.path("kind").asText("CATALOG");
            boolean errand = kind.startsWith("BUTLER");

            // Who must be present depends on what this is. A basket needs the shop that sold it; an
            // errand needs the rider who ran it, because they are the one owed the money. Demanding
            // a merchant of an errand is what left the first Butler orders unsettled entirely.
            String payee = errand ? riderId : merchantId;
            if (customerId == null || payee == null || total.isMissingNode() || total.isNull()) {
                // Acked, not requeued: a malformed event would otherwise loop forever and block
                // every settlement behind it. The absence of transaction rows for this order is
                // what the reconciliation view will show.
                log.error("Cannot settle {} order {} - event is missing parties or total: {}",
                        kind, event.path("orderId").asText("?"), payload);
                return;
            }

            // Absent on events published before the delivery fee existed. Null means "no
            // breakdown known", and settle() falls back to treating the whole total as goods —
            // which is exactly what those older orders were.
            JsonNode subtotal = event.path("subtotal");
            BigDecimal merchantBase = subtotal.isMissingNode() || subtotal.isNull()
                    ? null
                    : new BigDecimal(subtotal.asText());

            // The gate that stops the platform paying a merchant out of money nobody collected.
            //
            // Delivery and payment are the same moment for cash, so a cash order arrives here
            // COLLECTED. A card order does not: no provider is integrated, so it is delivered but
            // still AUTHORIZATION_PENDING. Settling it would credit a merchant against funds that
            // do not exist and take a commission on them.
            //
            // Absent on events published before payment methods existed; those were all cash,
            // collected at the door, so a missing status settles as it always did.
            String paymentStatus = event.path("paymentStatus").asText(null);
            if (paymentStatus != null && !SETTLEABLE.contains(paymentStatus)) {
                log.warn("Not settling order {} - delivered but payment is {}. "
                        + "It will show as unsettled in reconciliation until the money is taken.",
                        orderId, paymentStatus);
                return;
            }

            // Who is holding the money, which is not the same question as who owes it.
            //
            // On a card order the money moved between bank accounts and nobody is carrying
            // anything, so there is no holder and the customer is debited as before. On a cash
            // order the customer handed notes to whoever turned up — the ledger records that as an
            // obligation against them rather than pretending a bank account moved.
            //
            // A cash order with no rider on it cannot say who took the money, so it falls back to
            // the old approximation rather than inventing a holder. That should not happen: nobody
            // delivered it.
            SettlementService.CashHolder holder = null;
            if ("CASH".equals(event.path("paymentMethod").asText(null))) {
                if (riderId != null) {
                    holder = new SettlementService.CashHolder(
                            riderId, CashFloatEntry.HolderKind.RIDER);
                } else {
                    log.warn("Order {} was paid in cash but names no rider; recording the "
                            + "collection against the customer, which overstates their account.",
                            orderId);
                }
            }
            // Who carried it, and where they are paid. Null for the platform's own riders, which
            // is what keeps the delivery fee with the platform exactly as it always was.
            String carrierAccount = event.path("deliveryProviderAccount").asText(null);

            if (errand) {
                // The goods subtotal is what the rider spent out of pocket, and zero on a SEND.
                // Not the same figure as a merchant base: it is reimbursed in full rather than
                // being the base a commission is taken from.
                settlements.settleErrand(
                        orderId,
                        new BigDecimal(total.asText()),
                        merchantBase == null ? BigDecimal.ZERO : merchantBase,
                        accounts.forUser(customerId),
                        accounts.forUser(riderId),
                        holder, correlationId);
            } else {
                // What the platform absorbed, as decided when the order was placed. Absent on
                // events published before waivers existed, which settle exactly as they always did.
                JsonNode fee = event.path("deliveryFee");
                SettlementService.Waivers waivers = new SettlementService.Waivers(
                        fee.isNumber() ? fee.decimalValue() : null,
                        event.path("deliveryFeeWaived").asBoolean(false),
                        event.path("merchantFeeWaived").asBoolean(false),
                        event.path("carrierFeeWaived").asBoolean(false));

                settlements.settle(
                        orderId,
                        new BigDecimal(total.asText()),
                        merchantBase,
                        accounts.forUser(customerId),
                        accounts.forUser(merchantId),
                        carrierAccount,
                        holder, correlationId, waivers);
            }

            // Points, which is what the merchant and the carrier can actually convert into money.
            //
            // AFTER settlement and deliberately not inside it. The ledger above records who is owed
            // what and would be the source of a bank posting; points are what the platform pays
            // out today. Keeping them separate is what lets the bank path come back without
            // unpicking the reward scheme, and vice versa.
            //
            // In its own try: a points failure must not stop a settled order being settled. The
            // ledger is the record that matters, and points can be adjusted by an operator; losing
            // the settlement to a points bug cannot be repaired the same way.
            try {
                awardPoints(event, orderId, merchantId, riderId, errand);
            } catch (Exception e) {
                log.error("Settled order {} but could not award points", orderId, e);
            }

        } catch (Exception e) {
            log.error("Could not start settlement for event: {}", payload, e);

        } finally {
            if (correlationId != null) {
                MDC.remove("correlationId");
            }
        }
    }

    /**
     * Works out who earned what, and from which amount.
     *
     * <p>The shop earns on the goods it sold; whoever carried the order earns on the delivery fee.
     * Both from the total would pay each of them for the other's work.
     *
     * <p>An errand has no shop — the rider bought the goods themselves and is reimbursed, not
     * commissioned — so only the delivery half is awarded.
     *
     * <p>{@code deliveryProviderId} names the fleet and {@code deliveryProviderAccount} is null for
     * the platform's own riders. That null is the discriminator: a rider with a company behind them
     * earns into the company's balance tagged with their id, and a platform rider holds their own.
     * Reusing the existing field rather than adding one keeps the event shape unchanged.
     */
    private void awardPoints(JsonNode event, UUID orderId, String merchantId, String riderId,
                             boolean errand) {

        JsonNode fee = event.path("deliveryFee");
        BigDecimal deliveryFee = fee.isNumber() ? fee.decimalValue() : null;

        JsonNode subtotal = event.path("subtotal");
        BigDecimal goods = subtotal.isNumber() ? subtotal.decimalValue() : null;

        String carrierAccount = event.path("deliveryProviderAccount").asText(null);
        String carrierRef = carrierAccount == null
                ? null
                : event.path("deliveryProviderId").asText(null);

        points.awardForDelivery(
                orderId,
                // No shop earns on an errand: there was not one.
                errand ? null : merchantId,
                goods,
                riderId,
                carrierRef,
                deliveryFee);
    }
}
