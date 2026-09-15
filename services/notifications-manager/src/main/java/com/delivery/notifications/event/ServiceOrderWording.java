package com.delivery.notifications.event;

import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * What a service order is told that a basket is not, and the facts on its snapshot it is told from.
 *
 * <p>A service order (kind SERVICE: a print job, an alteration, a repair) moves on the same
 * {@code order.*} events and the same status machine as a basket, so {@link OrderEventListener}'s
 * audiences mostly hold for it. The basket's wording does not. "The restaurant has accepted your
 * order" is wrong for business cards, and "ready and waiting for a rider" is a promise nobody keeps
 * for an order its customer collects. So a service order's moments go out under event types of
 * their own, whose rows V19 holds, and this class is the one place that knows which moment is which
 * and fills the values those rows read. The listener goes on answering only who hears about it.
 *
 * <p><strong>A basket until the snapshot says otherwise.</strong> An order is a service order here
 * only when its snapshot says SERVICE <em>and</em> names a fulfilment this class knows. An event
 * published before order-manager carried either field is a basket's, which is what it was. An
 * unfamiliar fulfilment is not guessed at, because "ready to collect" said of an order a rider is
 * bringing is worse than the basket's generic sentence.
 *
 * <p>Nothing here reads the delivery address or the pins: a pickup has neither, and none of V19's
 * rows asks for them.
 */
final class ServiceOrderWording {

    private static final Logger log = LoggerFactory.getLogger(ServiceOrderWording.class);

    /** V19's event types. Each starts with its domain event, for the reasons V19 gives. */
    static final String PLACED_MERCHANT = "order.placed.service.merchant";
    static final String ACCEPTED = "order.status_changed.service.accepted";
    static final String READY_TO_COLLECT = "order.status_changed.service.ready_to_collect";
    static final String READY_FOR_RIDER = "order.status_changed.service.ready_for_rider";
    static final String COLLECTED = "order.delivered.service.collected";
    static final String DECLINED = "order.cancelled.service.declined";
    static final String NOT_COLLECTED = "order.cancelled.service.not_collected";

    /** The basket's status row, for the moments whose basket sentence already reads right. */
    private static final String STATUS_CHANGED = "order.status_changed";

    /**
     * Lebanon's clock, not the pod's and not UTC. A job due at 4:30 PM in Beirut announced as
     * "ready by 1:30 PM" sends somebody to the counter three hours early.
     */
    static final ZoneId LEBANON = ZoneId.of("Asia/Beirut");

    /**
     * The date as well as the time, always. This text is kept, in the inbox and in the notification
     * shade, and "tomorrow" read the next day is a day wrong.
     */
    private static final DateTimeFormatter READY_BY =
            DateTimeFormatter.ofPattern("EEE d MMM, h:mm a", Locale.ENGLISH).withZone(LEBANON);

    /** Lebanese month names (أيلول, not سبتمبر), which ar-LB carries, with Western digits. */
    private static final DateTimeFormatter READY_BY_AR =
            DateTimeFormatter.ofPattern("EEEE d MMMM، h:mm a", Locale.forLanguageTag("ar-LB"))
                    .withZone(LEBANON);

    /** How order-manager stores a provider's decline: {@code PROVIDER_DECLINED: TOO_BUSY}. */
    private static final String DECLINED_PREFIX = "PROVIDER_DECLINED";

    /** And a pickup nobody came for: {@code NOT_COLLECTED}, or {@code NOT_COLLECTED: the shop's words}. */
    private static final String NOT_COLLECTED_PREFIX = "NOT_COLLECTED";

    /** How the work reaches its customer. */
    enum Fulfilment {
        DELIVERY,
        PICKUP
    }

    private ServiceOrderWording() {
    }

    /** A service order's fulfilment, or empty for every order that is to be told as a basket. */
    static Optional<Fulfilment> of(JsonNode event) {
        if (!"SERVICE".equals(event.path("kind").asText(""))) {
            return Optional.empty();
        }
        return switch (event.path("fulfilment").asText("")) {
            case "PICKUP" -> Optional.of(Fulfilment.PICKUP);
            case "DELIVERY" -> Optional.of(Fulfilment.DELIVERY);
            default -> Optional.empty();
        };
    }

    /**
     * Adds the values V19's rows read to the basket's. Every one is a string and never null, so an
     * absent field renders as nothing rather than as "null" in somebody's text message.
     */
    static void addPlaceholders(JsonNode event, Fulfilment fulfilment, Map<String, String> values) {
        values.put("store", event.path("storeName").asText("").strip());
        values.put("offer", offer(event.path("items").path(0), values.getOrDefault("shortId", "")));

        Instant readyAt = instant(event.path("estimatedReadyAt"));
        values.put("readyBy", readyAt == null ? "" : READY_BY.format(readyAt));
        values.put("readyByAr", readyAt == null ? "" : READY_BY_AR.format(readyAt));

        // Words only for a cancellation told as the shop's own decision. Any other goes out on the
        // basket's rows, which read the reason as it was given.
        String reason = event.path("cancelReason").asText("");
        String cancelled = cancelledType(event, fulfilment);
        values.put("reasonWords", reasonWords(cancelled, reason, false));
        values.put("reasonWordsAr", reasonWords(cancelled, reason, true));

        if ("ACCEPTED".equals(event.path("status").asText(""))) {
            // The basket's sentence for ACCEPTED names a restaurant. A service order only reaches
            // the basket's row when it has no estimate to give (see statusChangedType), and
            // order-manager sets the estimate in the same step as the status, so that is a broken
            // event: said without a time, and logged rather than passed over.
            values.put("statusMessage", "Your order has been accepted.");
            if (readyAt == null) {
                log.warn("Service order {} was accepted with no readable estimatedReadyAt ({}); "
                                + "its customer is told without a time",
                        values.get("orderId"), event.path("estimatedReadyAt"));
            }
        }
    }

    /**
     * What a service order's status change goes out as: one of V19's moments, the basket's own row
     * where the basket's sentence already reads right, or null for nothing at all.
     *
     * <ul>
     *   <li><b>ACCEPTED</b> says when the work will be ready. With no estimate to give, it falls back
     *       to the basket's row with a sentence that names no restaurant, rather than to a row that
     *       ends in "ready by".</li>
     *   <li><b>PREPARING</b> says nothing. The shop accepts straight into production, so PREPARING
     *       arrives in the same second as the ACCEPTED that has just told the customer when to expect
     *       the work. Each transition has its own dedupe key, so nothing else would stop a second
     *       buzz that says less than the first.</li>
     *   <li><b>READY</b> says where the work is: at the counter, or waiting for a rider to be found.</li>
     *   <li>Anything else, which is PICKED_UP on a delivery, is about the rider, and the basket's
     *       sentence says that.</li>
     * </ul>
     */
    static String statusChangedType(String status, Fulfilment fulfilment, Map<String, String> values) {
        return switch (status) {
            case "ACCEPTED" -> values.getOrDefault("readyBy", "").isEmpty() ? STATUS_CHANGED : ACCEPTED;
            case "PREPARING" -> null;
            case "READY" -> fulfilment == Fulfilment.PICKUP ? READY_TO_COLLECT : READY_FOR_RIDER;
            default -> STATUS_CHANGED;
        };
    }

    /**
     * The moment a service order's cancellation goes out as when the snapshot shows it was its own
     * shop's decision on the list: a decline, or a pickup nobody collected. Null for every other
     * cancellation, which goes out on the basket's rows, to the customer and the shop both, in the
     * words it was given.
     *
     * <p><strong>A code in the reason is not proof of who cancelled.</strong> The snapshot names no
     * canceller and carries no status history, only the reason order-manager stored, and a reason is
     * somebody's own words wherever it is not one of a provider's two codes. Believed from the text
     * alone, a back-office cancel that began "PROVIDER_DECLINED" told the customer the shop had
     * declined and never told the shop, and a shop's own words beginning "NOT_COLLECTED" on an order
     * a rider was bringing said it had not been collected in time. order-manager is meant to keep both
     * codes to a provider's own two decisions; this does not lean on that alone. Each code is believed
     * only where order-manager itself could have written it:
     * <ul>
     *   <li><b>A decline</b> only on an order its shop never accepted. A provider declines a new
     *       order, and order-manager sets {@code estimatedReadyAt} in the same step as ACCEPTED and
     *       never clears it, so any estimate on the snapshot, readable or not, means the shop took the
     *       work on and whoever cancelled it afterwards did not decline it.</li>
     *   <li><b>Not collected</b> only on a PICKUP its shop accepted. Nothing a rider carries waits at
     *       a counter, and nothing waits there before it has been accepted.</li>
     *   <li>Either code only exactly as order-manager writes it: in capitals, at the very start.
     *       "Provider declined: closed today" is somebody's sentence.</li>
     * </ul>
     * Falling back is the cheap mistake. The customer reads the reason as it was given, and a shop
     * that did make the cancellation is told about it, as a basket's shop always is.
     */
    static String cancelledType(JsonNode event, Fulfilment fulfilment) {
        String reason = event.path("cancelReason").asText("");
        boolean accepted = !event.path("estimatedReadyAt").asText("").isBlank();
        if (!accepted && after(reason, DECLINED_PREFIX) != null) {
            return DECLINED;
        }
        if (accepted && fulfilment == Fulfilment.PICKUP && after(reason, NOT_COLLECTED_PREFIX) != null) {
            return NOT_COLLECTED;
        }
        return null;
    }

    /**
     * The job as the provider's own order card reads it: "500 Business Cards", packs times the
     * pack's size and then the offer's name. One unit is just the name. A service order is one offer,
     * so its first line is the job; with no name to give, the order number, so that "New service
     * order:" is never left hanging.
     */
    private static String offer(JsonNode line, String shortId) {
        String name = line.path("productName").asText("").strip();
        if (name.isEmpty()) {
            return "#" + shortId;
        }
        long units = Math.max(1, line.path("qty").asLong(1))
                * Math.max(1, line.path("service").path("unitSize").asLong(1));
        return units > 1 ? String.format(Locale.ENGLISH, "%,d %s", units, name) : name;
    }

    /** An ISO-8601 instant, as order-manager's outbox writes one, or null. */
    private static Instant instant(JsonNode node) {
        String text = node.asText("");
        if (text.isBlank()) {
            return null;
        }
        try {
            return Instant.parse(text);
        } catch (DateTimeParseException unreadable) {
            return null;
        }
    }

    /**
     * A cancellation's reason in words, for the moment {@link #cancelledType} made of it: a decline's
     * code as its customer should read it, the shop's own words after NOT_COLLECTED, or nothing.
     */
    private static String reasonWords(String cancelled, String reason, boolean arabic) {
        if (DECLINED.equals(cancelled)) {
            Decline decline = Decline.of(after(reason, DECLINED_PREFIX));
            return arabic ? decline.arabic : decline.english;
        }
        return NOT_COLLECTED.equals(cancelled) ? after(reason, NOT_COLLECTED_PREFIX) : "";
    }

    /**
     * What follows a stored code: "" after the bare code, the text after "CODE:" otherwise, or null
     * when the reason does not begin with the code exactly as order-manager writes it. Case and place
     * both count: "NOT_COLLECTEDX", "Not_Collected" and " NOT_COLLECTED" are not NOT_COLLECTED.
     */
    private static String after(String reason, String prefix) {
        if (reason == null || !reason.startsWith(prefix)) {
            return null;
        }
        String rest = reason.substring(prefix.length()).strip();
        if (rest.isEmpty()) {
            return "";
        }
        return rest.startsWith(":") ? rest.substring(1).strip() : null;
    }

    /**
     * A provider's decline picklist, in its customer's words.
     *
     * <p>Mirrors order-manager's DeclineReason. Each reads on from "Declined by Print Hub:", which the
     * provider's own labels ("We can't do this job") cannot, being in the wrong person. A code this
     * list does not know yet reads as OTHER, which is true of any reason a provider picks.
     */
    private enum Decline {
        TOO_BUSY("they're too busy right now", "مشغول جدًا حاليًا"),
        CANNOT_DO("they can't do this job", "لا يستطيع تنفيذ هذا العمل"),
        FILE_PROBLEM("there's a problem with your file", "هناك مشكلة في ملفك"),
        OTHER("they can't take this order", "لا يستطيع قبول هذا الطلب");

        private final String english;
        private final String arabic;

        Decline(String english, String arabic) {
            this.english = english;
            this.arabic = arabic;
        }

        static Decline of(String code) {
            for (Decline decline : values()) {
                if (decline.name().equalsIgnoreCase(code)) {
                    return decline;
                }
            }
            return OTHER;
        }
    }
}
