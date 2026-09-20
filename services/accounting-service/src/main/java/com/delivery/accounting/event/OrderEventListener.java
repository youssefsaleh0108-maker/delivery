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
import com.delivery.accounting.service.RiderEarningsService;
import com.delivery.accounting.service.SettlementFailureLog;
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
    private final RiderEarningsService riderEarnings;
    private final ObjectMapper objectMapper;
    private final SettlementFailureLog failures;

    /** Without a failure log: the shape for tests that are not about what cannot be settled. */
    public OrderEventListener(SettlementService settlements, AccountDirectory accounts,
                              PointsService points, RiderEarningsService riderEarnings,
                              ObjectMapper objectMapper) {
        this(settlements, accounts, points, riderEarnings, objectMapper, SettlementFailureLog.NONE);
    }

    @org.springframework.beans.factory.annotation.Autowired
    public OrderEventListener(SettlementService settlements, AccountDirectory accounts,
                              PointsService points, RiderEarningsService riderEarnings,
                              ObjectMapper objectMapper, SettlementFailureLog failures) {
        this.settlements = settlements;
        this.accounts = accounts;
        this.points = points;
        this.riderEarnings = riderEarnings;
        this.objectMapper = objectMapper;
        this.failures = failures;
    }

    /** Payment states in which the money has genuinely moved and settlement may proceed. */
    private static final java.util.Set<String> SETTLEABLE =
            java.util.Set.of("COLLECTED", "CAPTURED");

    /**
     * <strong>What happens when a settlement fails, which is the whole shape of this method
     * (RECON-04).</strong>
     *
     * <p>It used to catch every exception and return, which acknowledges the message. A database
     * blip while settling an {@code order.delivered} therefore lost that settlement for good: the
     * listener's own three attempts and the {@code accounting.order-events.dlq} never saw it,
     * nothing re-drove it, and no screen listed it, because every reconciliation view reads legs
     * that exist. The order stayed delivered in Order Manager and absent from the ledger, and the
     * shop, the carrier and the rider were never credited.
     *
     * <p>So a failure this service might survive — a timeout, a lost connection, a deadlock — is
     * rethrown: the container retries it and the broker dead-letters it, which is what both were
     * configured for. Only a message that will never settle is acknowledged: one that cannot be
     * parsed, one that names no parties or total, one whose money was never collected. Those are
     * recorded in {@link SettlementFailureLog} first, so the Back Office has an order to look at
     * rather than silence.
     */
    @RabbitListener(queues = "${delivery.accounting.order-events-queue:accounting.order-events}")
    public void onOrderEvent(String payload,
                             @Header(name = "eventType", required = false) String headerEventType,
                             @Header(name = "amqp_receivedRoutingKey", required = false) String routingKey,
                             @Header(name = "amqp_correlationId", required = false) String correlationId) {

        String eventType = headerEventType != null ? headerEventType : routingKey;
        if (!"order.delivered".equals(eventType) && !"order.tipped".equals(eventType)) {
            return;
        }

        if (correlationId != null) {
            MDC.put("correlationId", correlationId);
        }

        try {
            JsonNode event = objectMapper.readTree(payload);

            if ("order.tipped".equals(eventType)) {
                onOrderTipped(event);
                return;
            }

            Outcome outcome = settleDelivered(event, correlationId);
            if (!outcome.settled()) {
                failures.record(orderIdOf(event), eventType, outcome.reason(), payload,
                        correlationId);
            }

        } catch (com.fasterxml.jackson.core.JacksonException | IllegalArgumentException
                 | java.time.DateTimeException e) {
            // The message itself is wrong — bad JSON, an id that is not a uuid, an amount that is
            // not a number. Retrying cannot make it right, and requeueing a message that always
            // fails blocks every good one behind it. Acked, and written down where somebody can
            // see it rather than only in a log line nobody reads.
            log.error("Cannot settle this event and will not retry it: {}", payload, e);
            failures.record(orderIdOf(payload), eventType,
                    "The event could not be read: " + e.getMessage(), payload, correlationId);

        } finally {
            if (correlationId != null) {
                MDC.remove("correlationId");
            }
        }
    }

    /**
     * What a delivered order settled to, or why it did not.
     *
     * @param reason why nothing was settled, in the words an operator reads. Null when it settled
     */
    public record Outcome(boolean settled, String reason) {

        public static Outcome ok() {
            return new Outcome(true, null);
        }

        public static Outcome refused(String reason) {
            return new Outcome(false, reason);
        }
    }

    /**
     * Settles one delivered order from its snapshot.
     *
     * <p>Public because it is also how a settlement is re-driven: the Back Office's recovery
     * action reads the order from Order Manager, shapes it as this event, and settles it through
     * exactly these rules rather than a second implementation of them
     * ({@link com.delivery.accounting.service.SettlementRecovery}). Idempotent through
     * {@code SettlementService.settle}, which does nothing for an order that already has legs.
     *
     * @return {@link Outcome#refused} when this snapshot will never settle; anything that might
     *         succeed on a retry is thrown
     */
    public Outcome settleDelivered(JsonNode event, String correlationId) {
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
            // every settlement behind it. Recorded as a failure, because the absence of
            // transaction rows is exactly what no reconciliation view can show (RECON-04).
            log.error("Cannot settle {} order {} - event is missing parties or total",
                    kind, event.path("orderId").asText("?"));
            return Outcome.refused("The event names no " + (errand ? "rider" : "shop")
                    + ", no customer or no total, so there is nothing to settle from.");
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
            return Outcome.refused("Delivered, but the payment is " + paymentStatus
                    + ": nothing was collected, so nobody can be paid out of it.");
        }

        // Who is holding the money, which is not the same question as who owes it.
        //
        // On a card order the money moved between bank accounts and nobody is carrying
        // anything, so there is no holder and the customer is debited as before. On a cash
        // order the customer handed notes to whoever turned up — the ledger records that as an
        // obligation against them rather than pretending a bank account moved.
        //
        // A pickup is the one cash order nobody carries (a service order, V52): the customer pays
        // at the counter of the shop that did the work, so the SHOP is holding the notes and owes
        // them to the platform. Its collection is attributed to the shop and never to the
        // customer. Decided by the order's own fulfilment and never inferred from a missing
        // rider: a delivery that names no rider is a data problem, and charging its cash to the
        // shop would bill a merchant for notes a stranger took. Absent on every event published
        // before service orders — all of them deliveries — which settle exactly as they did.
        //
        // Any other cash order with no rider on it cannot say who took the money, so it falls
        // back to the old approximation rather than inventing a holder. That should not happen:
        // nobody delivered it.
        boolean pickup = "PICKUP".equals(event.path("fulfilment").asText(null));
        SettlementService.CashHolder holder = null;
        if ("CASH".equals(event.path("paymentMethod").asText(null))) {
            if (riderId != null) {
                holder = new SettlementService.CashHolder(
                        riderId, CashFloatEntry.HolderKind.RIDER,
                        carrierOwningTheCash(event, errand));
            } else if (pickup) {
                holder = new SettlementService.CashHolder(
                        merchantId, CashFloatEntry.HolderKind.MERCHANT);
            } else {
                log.warn("Order {} was paid in cash but names no rider; recording the "
                        + "collection against the customer, which overstates their account.",
                        orderId);
            }
        }
        // Who carried it, and where they are paid. Null for the platform's own riders, which
        // is what decides whether the fee is split with a company or with the rider directly.
        String carrierAccount = event.path("deliveryProviderAccount").asText(null);

        // The rider as a party in their own right, which is new: until the rider app had an
        // Earnings screen, a rider was only ever the person holding the cash. Null when the
        // event names nobody, and settlement is then byte-for-byte what it was.
        SettlementService.Rider rider = riderId == null ? null : new SettlementService.Rider(
                riderId,
                accounts.forUser(riderId),
                carrierAccount == null ? null : event.path("deliveryProviderId").asText(null),
                customerId);

        // When the work happened, so a rider's per-day statement buckets it on the day they
        // worked. Falls back to now for an event that does not carry it — which is every event
        // published before this existed — because a missing timestamp must not put a job in
        // 1970 and blank out the rider's week.
        java.time.Instant deliveredAt = timestampOf(event);

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
                    holder, correlationId, rider, deliveredAt);
        } else {
            // What the platform absorbed, as decided when the order was placed. Absent on
            // events published before waivers existed, which settle exactly as they always did.
            JsonNode fee = event.path("deliveryFee");
            // What a promo code took off the total. Read because totalAmount is already net of
            // it: without this the goods subtotal looks larger than the order and the merchant
            // base gets clamped down, paying the shop less than they sold to cover a promotion
            // the platform ran. See SettlementService.Waivers#discount.
            JsonNode discount = event.path("discountAmount");
            SettlementService.Waivers waivers = new SettlementService.Waivers(
                    fee.isNumber() ? fee.decimalValue() : null,
                    event.path("deliveryFeeWaived").asBoolean(false),
                    event.path("merchantFeeWaived").asBoolean(false),
                    event.path("carrierFeeWaived").asBoolean(false),
                    discount.isNumber() ? discount.decimalValue() : null);

            // What wrapping a gift added, paid in full to the shop that wrapped it. Read because
            // the total already includes it: unread, it fell into the platform's residue and was
            // reported as commission. Absent on events published before gifting and zero on
            // every other order, which then settle exactly as they always did.
            JsonNode wrap = event.path("giftWrapFee");

            // WHO, alongside WHERE THE MONEY GOES. Both identifiers were already parsed a few
            // lines above and then used only to look up an account — which is how the ledger
            // ended up unable to name a shop: `accounts.forUser` answers a different question,
            // and today it answers it with one omnibus bucket for every merchant on the
            // platform. Passing the ids as well costs nothing and is the whole fix.
            settlements.settle(
                    orderId,
                    new BigDecimal(total.asText()),
                    merchantBase,
                    accounts.forUser(customerId),
                    accounts.forUser(merchantId),
                    carrierAccount,
                    holder, correlationId, waivers, rider, deliveredAt,
                    new SettlementService.Parties(
                            merchantId, event.path("deliveryProviderId").asText(null)),
                    wrap.isNumber() ? wrap.decimalValue() : null);
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

        return Outcome.ok();
    }

    /** The order a message is about, or null when it does not name one this service can read. */
    private static UUID orderIdOf(JsonNode event) {
        try {
            String id = event.path("orderId").asText(null);
            return id == null || id.isBlank() ? null : UUID.fromString(id);
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    /** The same, from a message that may not even be JSON. */
    private UUID orderIdOf(String payload) {
        try {
            return orderIdOf(objectMapper.readTree(payload));
        } catch (RuntimeException | com.fasterxml.jackson.core.JacksonException e) {
            return null;
        }
    }

    /**
     * A tip added through Order Manager rather than through this service's own endpoint.
     *
     * <p><strong>A cross-service contract, and the shape is deliberate.</strong> The event must
     * carry the {@code customerId} that paid, because this service authorises a tip by matching it
     * against the customer on the delivered job — the same check the REST endpoint makes. An event
     * without it is refused rather than trusted: "it came off the bus" is not an authorisation, and
     * a tip that names no payer is a tip anybody could have caused.
     *
     * <p>Only a tip the platform has ALREADY COLLECTED belongs on this path, and nothing can
     * collect one today, so it is refused for the same reason the REST endpoint refuses an online
     * tip — see {@code RiderEarningsService.tip}. The handler exists so the contract is written
     * down and the wiring is real; what it cannot do is pretend money arrived.
     *
     * <p>Idempotent through the unique index on (order_id, rider_ref, entry_type): the bus is
     * at-least-once, and a redelivered tip must not pay the rider twice. A duplicate surfaces as
     * {@code IllegalStateException} and is acked as the no-op it is.
     */
    private void onOrderTipped(JsonNode event) {
        String orderId = event.path("orderId").asText(null);
        String customerId = event.path("customerId").asText(null);
        JsonNode amount = event.path("amount");

        if (orderId == null || customerId == null || !amount.isNumber()) {
            // Acked, not requeued, exactly as a malformed delivery event is: a bad message that
            // comes back forever blocks every good one behind it.
            log.error("Cannot record a tip - the event is missing the order, the payer or the "
                    + "amount: {}", event.path("orderId").asText("?"));
            return;
        }

        try {
            riderEarnings.tip(UUID.fromString(orderId), customerId, amount.decimalValue(),
                    RiderEarningsService.TipMethod.ONLINE);
        } catch (IllegalArgumentException | IllegalStateException e) {
            // Refused, and that is a fact worth a line rather than a stack trace: an online tip is
            // refused by design until there is a payment processor, and a redelivery is refused
            // because the tip is already recorded.
            log.warn("Tip on order {} not recorded: {}", orderId, e.getMessage());
        }
    }

    /**
     * The delivery company a cash order's notes are owed to, or null when they are owed to the
     * platform.
     *
     * <p>The owner's rule: a delivery company holds its riders' cash. So a catalog order carried by a
     * company's rider names that company, and the rider hands the notes to it rather than to the
     * platform. Decided by the same discriminator the fee split turns on —
     * {@code deliveryProviderAccount} is null for the platform's own riders — so the fee and the cash
     * can never disagree about which fleet carried the job.
     *
     * <p>Never for an errand. The rider fronted the goods on the platform's instruction and every row
     * of an errand is platform-payable whoever they ride for; a company that never saw that
     * transaction cannot be made answerable for its cash.
     */
    private static String carrierOwningTheCash(JsonNode event, boolean errand) {
        if (errand) {
            return null;
        }
        String carrierAccount = event.path("deliveryProviderAccount").asText(null);
        if (carrierAccount == null) {
            return null;
        }
        String providerId = event.path("deliveryProviderId").asText(null);
        return providerId == null || providerId.isBlank() ? null : providerId;
    }

    /**
     * When the order was delivered.
     *
     * <p>Tolerant of three names because the events on this bus were not written together, and
     * falls back to now rather than to null: a rider's statement buckets on this, and a missing
     * timestamp that became the epoch would move a day's work out of the week it was earned in and
     * blank the rider's screen.
     */
    private static java.time.Instant timestampOf(JsonNode event) {
        for (String field : java.util.List.of("deliveredAt", "occurredAt", "timestamp")) {
            String value = event.path(field).asText(null);
            if (value != null && !value.isBlank()) {
                try {
                    return java.time.Instant.parse(value);
                } catch (java.time.format.DateTimeParseException ignored) {
                    // Try the next name rather than failing the settlement over a format.
                }
            }
        }
        return java.time.Instant.now();
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

        JsonNode totalNode = event.path("totalAmount");
        BigDecimal total = totalNode.isNumber() ? totalNode.decimalValue() : null;

        points.awardForDelivery(
                orderId,
                // No shop earns on an errand: there was not one.
                errand ? null : merchantId,
                goods,
                riderId,
                carrierRef,
                deliveryFee,
                // The customer's loyalty points, on what they spent.
                event.path("customerId").asText(null),
                total);
    }
}
