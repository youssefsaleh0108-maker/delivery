package com.delivery.notifications.event;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.lang.reflect.Field;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.TreeSet;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.mockito.invocation.Invocation;
import org.slf4j.LoggerFactory;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;

import com.delivery.notifications.domain.NotificationCategory;
import com.delivery.notifications.domain.NotificationTemplate;
import com.delivery.notifications.service.NotificationDispatchService;
import com.delivery.notifications.service.RecipientDirectory;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * What a service order's customer and shop are told at each step, and proof that a basket's are
 * told exactly what they were.
 *
 * <p>Before V19 a service order was worded as a basket, and the order-manager review listed what
 * that did. Its customer read "The restaurant has accepted your order." and then, a second later,
 * a second push for PREPARING, because each transition carries its own dedupe key. A pickup was
 * "ready and waiting for a rider" nobody would send. The shop was told that a collection it had
 * tapped itself had "reached the customer". And the shop's new-order email offered "Deliver to:"
 * followed by nothing, since a pickup has no address.
 *
 * <p>Wording is asserted on the text a person would actually read: the values the listener builds,
 * rendered through the real {@link NotificationTemplate} against the rows the migrations insert,
 * read from the migration files themselves. So a placeholder the listener fills under one name and a
 * row reads under another fails here, not on somebody's phone.
 *
 * <p>Two more things are pinned because they cost money or trust when they drift: which moments send
 * a paid text, and that each English text stays one GSM-7 segment by the SMS worker's own alphabet;
 * and that a cancellation is told as the shop's own decision only where the snapshot shows the shop
 * could have made it.
 */
@DisplayName("service order notifications, and basket ones unchanged")
class OrderEventListenerTest {

    private static final ObjectMapper JSON = new ObjectMapper();
    private static final UUID ORDER = UUID.fromString("5e7a1c2d-8b3f-4a6e-9d10-2f4b6c8e0a13");
    private static final String SHORT_ID = "5E7A1C2D";
    private static final String CUSTOMER = "customer-sub";
    private static final String MERCHANT = "merchant-sub";
    private static final String RIDER = "rider-sub";

    /** Friday 18 September 2026, 4:30 PM in Beirut, which is UTC+3 in summer. */
    private static final String READY_AT = "2026-09-18T13:30:00Z";

    private static final String V19 = "V19__service_order_templates.sql";
    private static final Pattern TEMPLATE_ID =
            Pattern.compile("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}");

    /**
     * Every order template row the migrations insert, keyed "eventType|channel|locale". Inserts
     * only: V17's one UPDATE rewords the rider-assigned push, which nothing here renders.
     */
    private static final Map<String, NotificationTemplate> TEMPLATES = new LinkedHashMap<>();

    static {
        for (String file : List.of("V10__notifications.sql", "V11__audience_templates.sql",
                "V17__order_status_push.sql", "V18__order_push_gaps.sql", V19)) {
            for (List<String> row : rows(migration(file))) {
                TEMPLATES.put(row.get(1) + "|" + row.get(2) + "|" + row.get(3), template(row));
            }
        }
    }

    private NotificationDispatchService dispatch;
    private OrderEventListener listener;

    @BeforeEach
    void setUp() {
        dispatch = mock(NotificationDispatchService.class);
        RecipientDirectory recipients = mock(RecipientDirectory.class);
        when(recipients.contactsFor(anyString())).thenReturn(Map.of("PUSH", "device-token"));
        listener = new OrderEventListener(dispatch, recipients, JSON);
    }

    @Test
    @DisplayName("a pickup: the shop gets the job; the customer hears accepted with a time, ready to "
            + "collect, and is asked to rate")
    void pickupServiceOrder() {
        List<Sent> placed = deliver("order.placed", serviceOrder("PICKUP", "PLACED"));
        assertThat(routes(placed)).containsExactly(
                "order.placed -> " + CUSTOMER,
                "order.placed.service.merchant -> " + MERCHANT);
        assertThat(push(placed.get(1))).isEqualTo("New service order: 500 Business Cards");

        List<Sent> accepted = deliver("order.status_changed", accepted("PICKUP"));
        assertThat(routes(accepted))
                .containsExactly("order.status_changed.service.accepted -> " + CUSTOMER);
        assertThat(keys(accepted)).containsExactly(ORDER + ":ACCEPTED");
        assertThat(push(accepted.get(0)))
                .isEqualTo("Print Hub accepted your order — ready by Fri 18 Sep, 4:30 PM");

        assertThat(deliver("order.status_changed", serviceOrder("PICKUP", "PREPARING")))
                .as("PREPARING lands in the same second as the accept that already said when")
                .isEmpty();

        List<Sent> ready = deliver("order.status_changed", serviceOrder("PICKUP", "READY"));
        assertThat(routes(ready))
                .containsExactly("order.status_changed.service.ready_to_collect -> " + CUSTOMER);
        assertThat(keys(ready)).containsExactly(ORDER + ":READY");
        assertThat(push(ready.get(0))).isEqualTo("Ready to collect at Print Hub");

        List<Sent> collected = deliver("order.delivered", serviceOrder("PICKUP", "DELIVERED"));
        assertThat(routes(collected))
                .as("collected is the shop's own tap, so only the customer hears about it")
                .containsExactly("order.delivered.service.collected -> " + CUSTOMER);
        assertThat(keys(collected)).containsOnlyNulls();
        assertThat(push(collected.get(0))).isEqualTo("Collected — rate Print Hub");
    }

    @Test
    @DisplayName("a delivery: ready means a rider is being found, and from the rider on it reads as a "
            + "basket")
    void deliveryServiceOrder() {
        List<Sent> placed = deliver("order.placed", serviceOrder("DELIVERY", "PLACED"));
        assertThat(routes(placed)).containsExactly(
                "order.placed -> " + CUSTOMER,
                "order.placed.service.merchant -> " + MERCHANT);

        List<Sent> accepted = deliver("order.status_changed", accepted("DELIVERY"));
        assertThat(routes(accepted))
                .containsExactly("order.status_changed.service.accepted -> " + CUSTOMER);
        assertThat(keys(accepted)).containsExactly(ORDER + ":ACCEPTED");
        assertThat(push(accepted.get(0)))
                .isEqualTo("Print Hub accepted your order — ready by Fri 18 Sep, 4:30 PM");

        assertThat(deliver("order.status_changed", serviceOrder("DELIVERY", "PREPARING"))).isEmpty();

        List<Sent> ready = deliver("order.status_changed", serviceOrder("DELIVERY", "READY"));
        assertThat(routes(ready))
                .containsExactly("order.status_changed.service.ready_for_rider -> " + CUSTOMER);
        assertThat(keys(ready)).containsExactly(ORDER + ":READY");
        assertThat(push(ready.get(0))).isEqualTo("Ready — a rider is being assigned");

        List<Sent> claimed = deliver("order.rider_assigned",
                serviceOrder("DELIVERY", "READY").put("riderId", RIDER));
        assertThat(routes(claimed)).containsExactly(
                "order.rider_assigned -> " + CUSTOMER,
                "order.rider_assigned.rider -> " + RIDER);
        assertThat(body("order.rider_assigned.rider", "PUSH", "en", claimed.get(1).values()))
                .isEqualTo("Order #" + SHORT_ID + " — deliver to Mar Mikhael, Beirut.");

        List<Sent> pickedUp = deliver("order.status_changed",
                serviceOrder("DELIVERY", "PICKED_UP").put("riderId", RIDER));
        assertThat(routes(pickedUp)).containsExactly(
                "order.status_changed -> " + CUSTOMER,
                "order.status_changed.merchant -> " + MERCHANT);
        assertThat(keys(pickedUp)).containsExactly(ORDER + ":PICKED_UP", ORDER + ":PICKED_UP:merchant");
        assertThat(push(pickedUp.get(0)))
                .isEqualTo("Your rider has picked up your order and is on the way.");

        List<Sent> delivered = deliver("order.delivered",
                serviceOrder("DELIVERY", "DELIVERED").put("riderId", RIDER));
        assertThat(routes(delivered))
                .as("a rider brought it, so the shop is told as it is for a basket")
                .containsExactly(
                        "order.delivered -> " + CUSTOMER,
                        "order.delivered.merchant -> " + MERCHANT);
    }

    @Test
    @DisplayName("PREPARING follows a service order's accept in the same second, so it sends nothing; "
            + "a basket's still does")
    void noPreparingPushForAServiceOrder() {
        for (String fulfilment : List.of("PICKUP", "DELIVERY")) {
            assertThat(deliver("order.status_changed", serviceOrder(fulfilment, "PREPARING")))
                    .as("a %s service order's PREPARING", fulfilment)
                    .isEmpty();
        }

        assertThat(routes(deliver("order.status_changed", basket("PREPARING"))))
                .containsExactly("order.status_changed -> " + CUSTOMER);
    }

    @Test
    @DisplayName("a decline tells the customer who declined and why, in words, and does not read the "
            + "shop its own tap")
    void declineInWords() {
        Map<String, String> words = new LinkedHashMap<>();
        words.put("PROVIDER_DECLINED: TOO_BUSY", "they're too busy right now");
        words.put("PROVIDER_DECLINED: CANNOT_DO", "they can't do this job");
        words.put("PROVIDER_DECLINED: FILE_PROBLEM", "there's a problem with your file");
        words.put("PROVIDER_DECLINED: OTHER", "they can't take this order");
        // A code added to the picklist before this service has learned it is still a decline.
        words.put("PROVIDER_DECLINED: CLOSED_FOR_EID", "they can't take this order");

        words.forEach((reason, said) -> {
            List<Sent> sent = deliver("order.cancelled",
                    serviceOrder("PICKUP", "CANCELLED").put("cancelReason", reason));

            assertThat(routes(sent)).as(reason)
                    .containsExactly("order.cancelled.service.declined -> " + CUSTOMER);
            assertThat(push(sent.get(0))).as(reason).isEqualTo("Declined by Print Hub: " + said);
            String code = reason.substring(reason.indexOf(':') + 1).strip();
            assertThat(rowsFor("order.cancelled.service.declined"))
                    .as("the stored code is for machines")
                    .allSatisfy(row -> assertThat(rendered(row, sent.get(0).values()))
                            .doesNotContain("PROVIDER_DECLINED", code));
        });

        List<Sent> busy = deliver("order.cancelled",
                serviceOrder("DELIVERY", "CANCELLED").put("cancelReason", "PROVIDER_DECLINED: TOO_BUSY"));
        assertThat(body("order.cancelled.service.declined", "EMAIL", "en", busy.get(0).values()))
                .isEqualTo("Your order #" + SHORT_ID
                        + " was declined by Print Hub: they're too busy right now.");
        assertThat(body("order.cancelled.service.declined", "PUSH", "ar", busy.get(0).values()))
                .isEqualTo("رفض Print Hub طلبك: مشغول جدًا حاليًا");
    }

    @Test
    @DisplayName("a pickup nobody came for says so plainly, with the shop's own words when it gave any")
    void uncollectedPickup() {
        List<Sent> bare = deliver("order.cancelled", cancelledAfterAccept("PICKUP", "NOT_COLLECTED"));
        assertThat(routes(bare))
                .as("the shop cancelled it itself, so only the customer hears about it")
                .containsExactly("order.cancelled.service.not_collected -> " + CUSTOMER);
        assertThat(push(bare.get(0)))
                .isEqualTo("Print Hub cancelled your order because it wasn't collected in time.");

        List<Sent> worded = deliver("order.cancelled",
                cancelledAfterAccept("PICKUP", "NOT_COLLECTED: We kept it for a week"));
        assertThat(push(worded.get(0))).isEqualTo("Print Hub cancelled your order because it wasn't "
                + "collected in time. We kept it for a week");
        assertThat(body("order.cancelled.service.not_collected", "PUSH", "ar", worded.get(0).values()))
                .isEqualTo("ألغى Print Hub طلبك لأنه لم يُستلم في الوقت المحدد. We kept it for a week");
    }

    @Test
    @DisplayName("a code the snapshot cannot pin on the shop's own decision goes out as a basket's "
            + "cancellation, to the customer and the shop, in the words it was given")
    void cancelCodesNotPinnedOnTheShop() {
        Map<String, ObjectNode> cancels = new LinkedHashMap<>();
        // Back office stopping work the shop had accepted, in words that begin with the decline code.
        // The shop took the job on, so it did not decline it, and it has to be told to stop.
        cancels.put("a decline code after the shop accepted",
                cancelledAfterAccept("DELIVERY", "PROVIDER_DECLINED: TOO_BUSY"));
        // A shop's own words on an order a rider was bringing: nothing was waiting to be collected.
        cancels.put("not collected on a delivery",
                cancelledAfterAccept("DELIVERY", "NOT_COLLECTED: the customer never answered"));
        // Never accepted, so never ready at the counter, so never left uncollected.
        cancels.put("not collected before the shop accepted",
                cancelledBeforeAccept("PICKUP", "NOT_COLLECTED"));
        // Typed by a person: order-manager writes both codes in capitals, at the very start.
        cancels.put("a decline code in lower case",
                cancelledBeforeAccept("PICKUP", "provider_declined: too_busy"));
        cancels.put("not collected in mixed case",
                cancelledAfterAccept("PICKUP", "Not_Collected: we closed early"));

        cancels.forEach((why, event) -> {
            List<Sent> sent = deliver("order.cancelled", event);

            assertThat(routes(sent)).as(why).containsExactly(
                    "order.cancelled -> " + CUSTOMER,
                    "order.cancelled.merchant -> " + MERCHANT);
            assertThat(push(sent.get(0))).as(why)
                    .isEqualTo("Your order was cancelled. " + event.path("cancelReason").asText());
            assertThat(sent.get(0).values()).as(why)
                    .containsEntry("reasonWords", "")
                    .containsEntry("reasonWordsAr", "");
        });
    }

    @Test
    @DisplayName("any other cancellation of a service order is in somebody's own words, and reaches "
            + "both sides as a basket's does")
    void serviceCancelInSomebodysOwnWords() {
        List<Sent> sent = deliver("order.cancelled",
                serviceOrder("DELIVERY", "CANCELLED").put("cancelReason", "Ordered the wrong size"));

        assertThat(routes(sent)).containsExactly(
                "order.cancelled -> " + CUSTOMER,
                "order.cancelled.merchant -> " + MERCHANT);
        assertThat(push(sent.get(0))).isEqualTo("Your order was cancelled. Ordered the wrong size");
    }

    @Test
    @DisplayName("a basket is told exactly what it was, by the same people, under the same dedupe keys")
    void basketWordingAndKeysUnchanged() {
        List<Sent> placed = deliver("order.placed", basket("PLACED"));
        assertThat(routes(placed)).containsExactly(
                "order.placed -> " + CUSTOMER,
                "order.placed.merchant -> " + MERCHANT);
        assertThat(keys(placed)).containsOnlyNulls();
        assertThat(push(placed.get(1))).isEqualTo("Order #" + SHORT_ID + " is waiting to be accepted.");
        assertThat(body("order.placed.merchant", "EMAIL", "en", placed.get(1).values()))
                .contains("Items: 1\nTotal: 12.50\nDeliver to: Hamra, Beirut");
        assertThat(placed.get(0).values())
                .as("no service value rides along on a basket")
                .doesNotContainKeys("store", "offer", "readyBy", "readyByAr", "reasonWords",
                        "reasonWordsAr");

        Map<String, String> sentences = new LinkedHashMap<>();
        sentences.put("ACCEPTED", "The restaurant has accepted your order.");
        sentences.put("PREPARING", "The restaurant is preparing your order.");
        sentences.put("READY", "Your order is ready and waiting for a rider.");
        sentences.forEach((status, sentence) -> {
            List<Sent> sent = deliver("order.status_changed", basket(status));
            assertThat(routes(sent)).as(status).containsExactly("order.status_changed -> " + CUSTOMER);
            assertThat(keys(sent)).as(status).containsExactly(ORDER + ":" + status);
            assertThat(push(sent.get(0))).as(status).isEqualTo(sentence);
        });

        List<Sent> pickedUp = deliver("order.status_changed", basket("PICKED_UP"));
        assertThat(routes(pickedUp)).containsExactly(
                "order.status_changed -> " + CUSTOMER,
                "order.status_changed.merchant -> " + MERCHANT);
        assertThat(keys(pickedUp)).containsExactly(ORDER + ":PICKED_UP", ORDER + ":PICKED_UP:merchant");
        assertThat(push(pickedUp.get(0)))
                .isEqualTo("Your rider has picked up your order and is on the way.");

        List<Sent> claimed = deliver("order.rider_assigned", basket("READY"));
        assertThat(routes(claimed)).containsExactly(
                "order.rider_assigned -> " + CUSTOMER,
                "order.rider_assigned.rider -> " + RIDER);
        assertThat(keys(claimed)).containsOnlyNulls();

        List<Sent> delivered = deliver("order.delivered", basket("DELIVERED"));
        assertThat(routes(delivered)).containsExactly(
                "order.delivered -> " + CUSTOMER,
                "order.delivered.merchant -> " + MERCHANT);
        assertThat(keys(delivered)).containsOnlyNulls();
        assertThat(push(delivered.get(0))).isEqualTo("Order #" + SHORT_ID + " has arrived.");

        // A basket's reason can say anything; only a service order is read for the shop's codes.
        List<Sent> cancelled = deliver("order.cancelled",
                basket("CANCELLED").put("cancelReason", "PROVIDER_DECLINED: TOO_BUSY"));
        assertThat(routes(cancelled)).containsExactly(
                "order.cancelled -> " + CUSTOMER,
                "order.cancelled.merchant -> " + MERCHANT);
        assertThat(keys(cancelled)).containsOnlyNulls();
        assertThat(push(cancelled.get(0)))
                .isEqualTo("Your order was cancelled. PROVIDER_DECLINED: TOO_BUSY");
    }

    @Test
    @DisplayName("an event from before kind and fulfilment were published is a basket's, and so is a "
            + "service order that names no fulfilment")
    void eventsWithoutKindOrFulfilmentAreBaskets() {
        ObjectNode old = JSON.createObjectNode()
                .put("orderId", ORDER.toString())
                .put("customerId", CUSTOMER)
                .put("merchantId", MERCHANT)
                .put("status", "READY")
                .put("totalAmount", new BigDecimal("12.50"))
                .put("deliveryAddress", "Hamra, Beirut");

        List<Sent> ready = deliver("order.status_changed", old);
        assertThat(routes(ready)).containsExactly("order.status_changed -> " + CUSTOMER);
        assertThat(keys(ready)).containsExactly(ORDER + ":READY");
        assertThat(push(ready.get(0))).isEqualTo("Your order is ready and waiting for a rider.");

        assertThat(routes(deliver("order.placed", old.put("status", "PLACED")))).containsExactly(
                "order.placed -> " + CUSTOMER,
                "order.placed.merchant -> " + MERCHANT);

        ObjectNode noFulfilment = serviceOrder("PICKUP", "READY");
        noFulfilment.remove("fulfilment");
        assertThat(routes(deliver("order.status_changed", noFulfilment)))
                .as("not guessed at: 'ready to collect' said of an order a rider is bringing is worse")
                .containsExactly("order.status_changed -> " + CUSTOMER);
    }

    @Test
    @DisplayName("a pickup with no address and no pins goes through every step with no error, no "
            + "\"null\" and no row asking for an address")
    void pickupWithNoAddressOrPins() {
        Logger logger = (Logger) LoggerFactory.getLogger(OrderEventListener.class);
        ListAppender<ILoggingEvent> logged = new ListAppender<>();
        logged.start();
        logger.addAppender(logged);
        try {
            // Explicit nulls, as order-manager publishes a pickup, and the fields left out entirely.
            ObjectNode absent = serviceOrder("PICKUP", "PLACED");
            absent.remove(List.of("deliveryAddress", "pickupLat", "pickupLng", "dropoffLat", "dropoffLng"));

            List<List<Sent>> steps = List.of(
                    deliver("order.placed", serviceOrder("PICKUP", "PLACED")),
                    deliver("order.placed", absent),
                    deliver("order.status_changed", accepted("PICKUP")),
                    deliver("order.status_changed", serviceOrder("PICKUP", "READY")),
                    deliver("order.delivered", serviceOrder("PICKUP", "DELIVERED")),
                    deliver("order.cancelled", cancelledAfterAccept("PICKUP", "NOT_COLLECTED")),
                    deliver("order.cancelled", serviceOrder("PICKUP", "CANCELLED")
                            .put("cancelReason", "PROVIDER_DECLINED: TOO_BUSY")));

            assertThat(steps).as("every step still reached somebody")
                    .allSatisfy(step -> assertThat(step).isNotEmpty());
            assertThat(logged.list).as("nothing fell into the listener's catch-all")
                    .noneMatch(event -> event.getLevel().isGreaterOrEqual(Level.WARN));

            for (List<Sent> step : steps) {
                for (Sent sent : step) {
                    assertThat(sent.values()).as(sent.route())
                            .doesNotContainValue(null)
                            .doesNotContainValue("null");
                    // A marker where an address would go finds any row that asks for one: on a
                    // pickup it would render blank, as the basket's "Deliver to:" email did.
                    Map<String, String> probe = new HashMap<>(sent.values());
                    probe.put("address", "<ADDRESS>");
                    assertThat(rowsFor(sent.eventType())).as(sent.route()).isNotEmpty()
                            .allSatisfy(row -> assertThat(rendered(row, probe))
                                    .as("%s %s %s", sent.eventType(), row.getChannel(), row.getLocale())
                                    .doesNotContain("null", "{{", "<ADDRESS>"));
                }
            }
        } finally {
            logger.detachAppender(logged);
        }
    }

    @Test
    @DisplayName("ready-by is Beirut's wall clock in summer and in winter, with the date written out")
    void readyByIsBeirutTime() {
        Map<String, String> summer = deliver("order.status_changed", accepted("PICKUP")).get(0).values();
        assertThat(summer)
                .containsEntry("readyBy", "Fri 18 Sep, 4:30 PM")
                .containsEntry("readyByAr", "الجمعة 18 أيلول، 4:30 م");

        Map<String, String> winter = deliver("order.status_changed", serviceOrder("PICKUP", "ACCEPTED")
                .put("estimatedReadyAt", "2026-01-18T08:05:00Z")).get(0).values();
        assertThat(winter)
                .as("UTC+2 once summer time ends")
                .containsEntry("readyBy", "Sun 18 Jan, 10:05 AM")
                .containsEntry("readyByAr", "الأحد 18 كانون الثاني، 10:05 ص");
    }

    @Test
    @DisplayName("an accept with no readable estimate is still said, without a time and without a "
            + "restaurant")
    void acceptedWithoutAnEstimate() {
        for (String estimate : new String[] {null, "next week"}) {
            ObjectNode event = serviceOrder("PICKUP", "ACCEPTED");
            if (estimate != null) {
                event.put("estimatedReadyAt", estimate);
            }

            List<Sent> sent = deliver("order.status_changed", event);
            assertThat(routes(sent)).as(String.valueOf(estimate))
                    .containsExactly("order.status_changed -> " + CUSTOMER);
            assertThat(keys(sent)).containsExactly(ORDER + ":ACCEPTED");
            assertThat(push(sent.get(0))).isEqualTo("Your order has been accepted.");
        }
    }

    @Test
    @DisplayName("V19 adds only service rows, on the same channels in English and Arabic, and every one "
            + "fills from a real event")
    void serviceRowsAndListenerAgree() {
        List<List<String>> v19 = rows(migration(V19));
        assertThat(v19).as("seven moments on three channels each in two languages, less the texts for "
                + "ready-for-a-rider and collected").hasSize(38);
        assertThat(v19).as("no basket row is added or replaced")
                .allSatisfy(row -> assertThat(row.get(1)).contains(".service"));
        assertThat(v19.stream().map(row -> row.get(1) + "|" + row.get(2) + "|" + row.get(3)))
                .doesNotHaveDuplicates();

        Map<String, Map<String, String>> byMoment = new LinkedHashMap<>();
        List.of(
                deliver("order.placed", serviceOrder("PICKUP", "PLACED")),
                deliver("order.status_changed", accepted("DELIVERY")),
                deliver("order.status_changed", serviceOrder("PICKUP", "READY")),
                deliver("order.status_changed", serviceOrder("DELIVERY", "READY")),
                deliver("order.delivered", serviceOrder("PICKUP", "DELIVERED")),
                deliver("order.cancelled", serviceOrder("PICKUP", "CANCELLED")
                        .put("cancelReason", "PROVIDER_DECLINED: FILE_PROBLEM")),
                deliver("order.cancelled", cancelledAfterAccept("PICKUP", "NOT_COLLECTED")))
                .forEach(step -> step.stream()
                        .filter(sent -> sent.eventType().contains(".service"))
                        .forEach(sent -> byMoment.put(sent.eventType(), sent.values())));

        assertThat(byMoment.keySet())
                .as("the listener sends every moment V19 has rows for")
                .containsExactlyInAnyOrderElementsOf(
                        v19.stream().map(row -> row.get(1)).distinct().toList());

        byMoment.forEach((moment, values) -> {
            assertThat(channels(moment, "ar")).as(moment)
                    .isEqualTo(channels(moment, "en"))
                    .isNotEmpty();
            assertThat(NotificationCategory.forEventType(moment))
                    .as("%s is governed by the customer's order-updates switch", moment)
                    .isEqualTo(NotificationCategory.ORDER_UPDATES);
            assertThat(rowsFor(moment)).allSatisfy(row -> assertThat(rendered(row, values))
                    .as("%s %s %s", moment, row.getChannel(), row.getLocale())
                    .doesNotContain("{{", "null"));
        });

        // The Arabic rows read Arabic values: neither the date nor a decline's reason stays English.
        assertThat(body(ServiceOrderWording.ACCEPTED, "PUSH", "ar",
                byMoment.get(ServiceOrderWording.ACCEPTED)))
                .isEqualTo("قبِل Print Hub طلبك — سيكون جاهزًا بحلول الجمعة 18 أيلول، 4:30 م");
        assertThat(body(ServiceOrderWording.DECLINED, "PUSH", "ar",
                byMoment.get(ServiceOrderWording.DECLINED)))
                .isEqualTo("رفض Print Hub طلبك: هناك مشكلة في ملفك");
    }

    @Test
    @DisplayName("texts are paid for: a delivery service order sends three (accepted, picked up, "
            + "delivered) and a pickup two (accepted, ready to collect), and Arabic texts the same moments")
    void textsPerServiceOrder() {
        List<Sent> delivery = new ArrayList<>();
        delivery.addAll(deliver("order.placed", serviceOrder("DELIVERY", "PLACED")));
        delivery.addAll(deliver("order.status_changed", accepted("DELIVERY")));
        delivery.addAll(deliver("order.status_changed", accepted("DELIVERY").put("status", "PREPARING")));
        delivery.addAll(deliver("order.status_changed", accepted("DELIVERY").put("status", "READY")));
        delivery.addAll(deliver("order.rider_assigned",
                accepted("DELIVERY").put("status", "READY").put("riderId", RIDER)));
        delivery.addAll(deliver("order.status_changed",
                accepted("DELIVERY").put("status", "PICKED_UP").put("riderId", RIDER)));
        delivery.addAll(deliver("order.delivered",
                accepted("DELIVERY").put("status", "DELIVERED").put("riderId", RIDER)));
        assertThat(texted(delivery))
                .as("ready-for-a-rider is not texted: the picked-up and delivered texts say somebody is coming")
                .containsExactly(
                        "order.status_changed.service.accepted -> " + CUSTOMER,
                        "order.status_changed -> " + CUSTOMER,
                        "order.delivered -> " + CUSTOMER);

        List<Sent> pickup = new ArrayList<>();
        pickup.addAll(deliver("order.placed", serviceOrder("PICKUP", "PLACED")));
        pickup.addAll(deliver("order.status_changed", accepted("PICKUP")));
        pickup.addAll(deliver("order.status_changed", accepted("PICKUP").put("status", "PREPARING")));
        pickup.addAll(deliver("order.status_changed", accepted("PICKUP").put("status", "READY")));
        pickup.addAll(deliver("order.delivered", accepted("PICKUP").put("status", "DELIVERED")));
        assertThat(texted(pickup))
                .as("collected is not texted: its customer is standing at the counter")
                .containsExactly(
                        "order.status_changed.service.accepted -> " + CUSTOMER,
                        "order.status_changed.service.ready_to_collect -> " + CUSTOMER);

        List<String> moments = rows(migration(V19)).stream().map(row -> row.get(1)).distinct().toList();
        assertThat(moments).allSatisfy(moment -> assertThat(channels(moment, "ar"))
                .as("%s in Arabic", moment)
                .isEqualTo(channels(moment, "en")));
        assertThat(moments.stream().filter(moment -> channels(moment, "en").contains("SMS")).toList())
                .containsExactlyInAnyOrder(ServiceOrderWording.ACCEPTED, ServiceOrderWording.READY_TO_COLLECT);
    }

    @Test
    @DisplayName("every English text is one GSM-7 segment by the SMS worker's own alphabet, with a "
            + "16-character shop name and the longest ready-by the formatter writes")
    void englishTextsAreOneGsmSegment() {
        Gsm gsm = Gsm.ofSmsPreparer();
        assertThat(gsm.encodes("Delivery: Print Hub accepted order #5E7A1C2D - ready by Fri 18 Sep, "
                + "4:30 PM.")).isTrue();
        assertThat(gsm.encodes("Delivery: Print Hub accepted order #5E7A1C2D — ready by Fri 18 Sep, "
                + "4:30 PM."))
                .as("the em dash V19's accept text had, which sent it as UCS-2 in two segments")
                .isFalse();

        // The longest value each placeholder takes over a delivery's life, from real events: a
        // 16-character shop name, the 8-character order number, and a ready-by with a two-digit day
        // and a two-digit hour.
        Map<String, String> longest = new HashMap<>();
        for (String[] step : new String[][] {
                {"order.placed", "PLACED"}, {"order.status_changed", "ACCEPTED"},
                {"order.status_changed", "READY"}, {"order.rider_assigned", "READY"},
                {"order.status_changed", "PICKED_UP"}, {"order.delivered", "DELIVERED"}}) {
            ObjectNode event = serviceOrder("DELIVERY", step[1])
                    .put("storeName", "Print Hub Beirut")
                    .put("estimatedReadyAt", "2026-09-30T09:59:00Z")
                    .put("riderId", RIDER);
            deliver(step[0], event).forEach(sent -> sent.values().forEach((key, value) ->
                    longest.merge(key, value, (kept, other) -> kept.length() >= other.length() ? kept : other)));
        }
        assertThat(longest)
                .containsEntry("store", "Print Hub Beirut")
                .containsEntry("shortId", SHORT_ID)
                .containsEntry("readyBy", "Wed 30 Sep, 12:59 PM");

        List<NotificationTemplate> englishTexts = TEMPLATES.values().stream()
                .filter(row -> "SMS".equals(row.getChannel()) && "en".equals(row.getLocale()))
                .toList();
        assertThat(englishTexts).extracting(NotificationTemplate::getEventType)
                .as("the service texts are among those checked")
                .contains(ServiceOrderWording.ACCEPTED, ServiceOrderWording.READY_TO_COLLECT);

        for (NotificationTemplate row : englishTexts) {
            String text = row.renderBody(longest);
            assertThat(text).as(row.getEventType()).doesNotContain("{{");
            assertThat(text.chars().filter(c -> !gsm.encodes(Character.toString(c)))
                    .mapToObj(Character::toString).toList())
                    .as("%s: characters outside GSM-7 in \"%s\"", row.getEventType(), text)
                    .isEmpty();
            assertThat(gsm.units(text))
                    .as("%s: \"%s\" in one segment", row.getEventType(), text)
                    .isLessThanOrEqualTo(gsm.singleSegment());
        }
    }

    // ------------------------------------------------------------------------------------- events

    /** A service order's snapshot as order-manager publishes it: no customer name, no instructions. */
    private static ObjectNode serviceOrder(String fulfilment, String status) {
        ObjectNode event = JSON.createObjectNode()
                .put("orderId", ORDER.toString())
                .put("kind", "SERVICE")
                .put("fulfilment", fulfilment)
                .put("customerId", CUSTOMER)
                .put("merchantId", MERCHANT)
                .put("status", status)
                .put("totalAmount", new BigDecimal("15.00"))
                .put("storeName", "Print Hub")
                .put("serviceCategory", "PRINTING")
                .put("pickupLat", new BigDecimal("33.8959"))
                .put("pickupLng", new BigDecimal("35.5189"))
                .put("placedAt", "2026-09-16T13:30:00Z")
                .put("occurredAt", "2026-09-16T13:31:00Z");
        event.putNull("riderId");
        event.putNull("estimatedReadyAt");
        event.putNull("cancelReason");
        if ("PICKUP".equals(fulfilment)) {
            // Nobody carries a pickup: no address, and nowhere to drop it.
            event.putNull("deliveryAddress");
            event.putNull("dropoffLat");
            event.putNull("dropoffLng");
        } else {
            event.put("deliveryAddress", "Mar Mikhael, Beirut");
            event.put("dropoffLat", new BigDecimal("33.8970"));
            event.put("dropoffLng", new BigDecimal("35.5250"));
        }
        ObjectNode line = event.putArray("items").addObject()
                .put("productId", "0b8f7c1e-3d2a-4f5b-8c6d-7e9f0a1b2c3d")
                .put("productName", "Business Cards")
                .put("unitPrice", new BigDecimal("15.00"))
                .put("qty", 1);
        line.putObject("service")
                .put("pricingType", "FIXED")
                .put("unitLabel", "cards")
                .put("unitSize", 500)
                .put("turnaroundMinHours", 24)
                .put("turnaroundMaxHours", 48)
                .put("attachmentPolicy", "OPTIONAL");
        return event;
    }

    /** Accepted, carrying the estimate order-manager sets in the same step. */
    private static ObjectNode accepted(String fulfilment) {
        return serviceOrder(fulfilment, "ACCEPTED").put("estimatedReadyAt", READY_AT);
    }

    /** Cancelled after its shop accepted it: the estimate set then stays on the order. */
    private static ObjectNode cancelledAfterAccept(String fulfilment, String reason) {
        return accepted(fulfilment).put("status", "CANCELLED").put("cancelReason", reason);
    }

    /** Cancelled before anybody accepted it, so no estimate was ever set. */
    private static ObjectNode cancelledBeforeAccept(String fulfilment, String reason) {
        return serviceOrder(fulfilment, "CANCELLED").put("cancelReason", reason);
    }

    /** A basket's snapshot, as it was before service orders and as it still is. */
    private static ObjectNode basket(String status) {
        ObjectNode event = JSON.createObjectNode()
                .put("orderId", ORDER.toString())
                .put("kind", "CATALOG")
                .put("fulfilment", "DELIVERY")
                .put("customerId", CUSTOMER)
                .put("merchantId", MERCHANT)
                .put("riderId", RIDER)
                .put("status", status)
                .put("totalAmount", new BigDecimal("12.50"))
                .put("storeName", "Hamra Grill")
                .put("deliveryAddress", "Hamra, Beirut");
        event.putNull("cancelReason");
        event.putArray("items").addObject()
                .put("productName", "Shawarma")
                .put("qty", 2)
                .putNull("service");
        return event;
    }

    // ---------------------------------------------------------------------------------- dispatches

    /** One dispatch the listener asked for. */
    private record Sent(String eventType, String recipient, Map<String, String> values, String dedupeKey) {

        String route() {
            return eventType + " -> " + recipient;
        }
    }

    /** Delivers one event and returns what it dispatched, and nothing from before it. */
    private List<Sent> deliver(String eventType, ObjectNode event) {
        Mockito.clearInvocations(dispatch);
        listener.onOrderEvent(event.toString(), eventType, eventType, "corr-1");

        List<Sent> sent = new ArrayList<>();
        for (Invocation call : Mockito.mockingDetails(dispatch).getInvocations()) {
            // The listener only ever calls the overload that takes a dedupe key.
            sent.add(new Sent(call.getArgument(0), call.getArgument(2), call.getArgument(4),
                    call.getArgument(6)));
        }
        return sent;
    }

    private static List<String> routes(List<Sent> sent) {
        return sent.stream().map(Sent::route).toList();
    }

    private static List<String> keys(List<Sent> sent) {
        return sent.stream().map(Sent::dedupeKey).toList();
    }

    /** The dispatches that go out as a text: those whose event type has an English SMS row. */
    private static List<String> texted(List<Sent> sent) {
        return sent.stream()
                .filter(one -> TEMPLATES.containsKey(one.eventType() + "|SMS|en"))
                .map(Sent::route)
                .toList();
    }

    // ----------------------------------------------------------------------------------- templates

    /** The English push a person would read for this dispatch. */
    private static String push(Sent sent) {
        return body(sent.eventType(), "PUSH", "en", sent.values());
    }

    private static String body(String eventType, String channel, String locale,
                               Map<String, String> values) {
        NotificationTemplate row = TEMPLATES.get(eventType + "|" + channel + "|" + locale);
        assertThat(row).as("a %s %s row for %s", locale, channel, eventType).isNotNull();
        return row.renderBody(values);
    }

    /** Subject and body as a notification shows them; a row with no subject contributes nothing. */
    private static String rendered(NotificationTemplate row, Map<String, String> values) {
        return Objects.toString(row.renderSubject(values), "") + "\n" + row.renderBody(values);
    }

    /** Every row for one event type, in every channel and locale. */
    private static List<NotificationTemplate> rowsFor(String eventType) {
        return TEMPLATES.entrySet().stream()
                .filter(entry -> entry.getKey().startsWith(eventType + "|"))
                .map(Map.Entry::getValue)
                .toList();
    }

    private static Set<String> channels(String eventType, String locale) {
        Set<String> channels = new TreeSet<>();
        for (String key : TEMPLATES.keySet()) {
            String[] parts = key.split("\\|");
            if (parts[0].equals(eventType) && parts[2].equals(locale)) {
                channels.add(parts[1]);
            }
        }
        return channels;
    }

    private static String migration(String file) {
        try (InputStream in = OrderEventListenerTest.class
                .getResourceAsStream("/db/migration/notification/" + file)) {
            assertThat(in).as(file).isNotNull();
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /**
     * The (id, event_type, channel, locale, subject_template, body_template) tuples a migration
     * inserts.
     *
     * <p>A reader for the SQL these files are written in, not a SQL parser: quoted and E'' literals,
     * doubled quotes and \n inside them, || between them, null, and -- comments. Every other
     * parenthesised group (a column list, a CHECK, an index) is dropped because it does not start
     * with a template id.
     */
    private static List<List<String>> rows(String sql) {
        List<List<String>> rows = new ArrayList<>();
        List<String> tuple = new ArrayList<>();
        StringBuilder value = null;
        int depth = 0;
        for (int i = 0; i < sql.length(); i++) {
            char c = sql.charAt(i);
            if (c == '-' && i + 1 < sql.length() && sql.charAt(i + 1) == '-') {
                int end = sql.indexOf('\n', i);
                i = end < 0 ? sql.length() : end;
            } else if (c == '\'' || startsEscapeString(sql, i)) {
                boolean escapes = c != '\'';
                i += escapes ? 2 : 1;
                if (value == null) {
                    value = new StringBuilder();
                }
                for (; ; i++) {
                    char d = sql.charAt(i);
                    if (escapes && d == '\\') {
                        char escaped = sql.charAt(++i);
                        value.append(escaped == 'n' ? '\n' : escaped);
                    } else if (d == '\'' && i + 1 < sql.length() && sql.charAt(i + 1) == '\'') {
                        value.append('\'');
                        i++;
                    } else if (d == '\'') {
                        break;
                    } else {
                        value.append(d);
                    }
                }
            } else if (c == '(') {
                if (++depth == 1) {
                    tuple = new ArrayList<>();
                    value = null;
                }
            } else if (c == ',' && depth == 1) {
                tuple.add(value == null ? null : value.toString());
                value = null;
            } else if (c == ')' && --depth == 0) {
                tuple.add(value == null ? null : value.toString());
                value = null;
                if (tuple.size() == 6 && tuple.get(0) != null
                        && TEMPLATE_ID.matcher(tuple.get(0)).matches()) {
                    rows.add(tuple);
                }
            }
        }
        return rows;
    }

    private static boolean startsEscapeString(String sql, int i) {
        char c = sql.charAt(i);
        return (c == 'E' || c == 'e')
                && i + 1 < sql.length() && sql.charAt(i + 1) == '\''
                && (i == 0 || !Character.isLetterOrDigit(sql.charAt(i - 1)) && sql.charAt(i - 1) != '_');
    }

    private static NotificationTemplate template(List<String> row) {
        try {
            var constructor = NotificationTemplate.class.getDeclaredConstructor();
            constructor.setAccessible(true);
            NotificationTemplate template = constructor.newInstance();
            set(template, "id", UUID.fromString(row.get(0)));
            set(template, "eventType", row.get(1));
            set(template, "channel", row.get(2));
            set(template, "locale", row.get(3));
            set(template, "subjectTemplate", row.get(4));
            set(template, "bodyTemplate", row.get(5));
            return template;
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
    }

    private static void set(NotificationTemplate target, String name, Object value)
            throws ReflectiveOperationException {
        Field field = NotificationTemplate.class.getDeclaredField(name);
        field.setAccessible(true);
        field.set(target, value);
    }

    // -------------------------------------------------------------------------------------- texts

    /**
     * The SMS worker's alphabet and single-segment limit, read out of SmsPreparer's source.
     *
     * <p>Read rather than copied: a copy here would agree with these templates forever, whatever the
     * worker counts and the vendor bills. Read from the file because sms-connector is a Spring Boot
     * application beside this one in the repository, not a library on its classpath.
     */
    private record Gsm(String alphabet, String extension, int singleSegment) {

        static Gsm ofSmsPreparer() {
            String source;
            try {
                source = Files.readString(smsPreparer(), StandardCharsets.UTF_8);
            } catch (IOException e) {
                throw new UncheckedIOException(e);
            }
            Matcher single = Pattern.compile("\\bGSM_SINGLE\\s*=\\s*(\\d+)\\s*;").matcher(source);
            assertThat(single.find()).as("SmsPreparer declares GSM_SINGLE").isTrue();

            Gsm gsm = new Gsm(stringConstant(source, "GSM_ALPHABET"),
                    stringConstant(source, "GSM_EXTENDED"), Integer.parseInt(single.group(1)));
            assertThat(gsm.alphabet()).as("GSM_ALPHABET as read from SmsPreparer")
                    .contains("@", "£", "A", "z", "0", "#", "-", ":", "€");
            return gsm;
        }

        boolean encodes(String text) {
            return text.chars().allMatch(c -> alphabet.indexOf(c) >= 0);
        }

        /** Billable units: a character from the extension table goes as an escape and itself. */
        int units(String text) {
            return text.chars().map(c -> extension.indexOf(c) >= 0 ? 2 : 1).sum();
        }

        /** SmsPreparer.java, found from wherever the build runs: this module or the repository root. */
        private static Path smsPreparer() {
            Path file = Path.of("sms-connector", "src", "main", "java", "com", "delivery", "connector",
                    "sms", "SmsPreparer.java");
            for (Path dir = Path.of("").toAbsolutePath(); dir != null; dir = dir.getParent()) {
                for (Path candidate : List.of(dir.resolve(file), dir.resolve("services").resolve(file))) {
                    if (Files.isRegularFile(candidate)) {
                        return candidate;
                    }
                }
            }
            throw new AssertionError("No SmsPreparer.java beside this module or under services/, "
                    + "looking up from " + Path.of("").toAbsolutePath());
        }

        /**
         * A String constant's value: its literals with their escapes, joined to any constant it adds.
         * Scanned rather than matched with a pattern, because the alphabet itself contains a ';'.
         */
        private static String stringConstant(String source, String name) {
            Matcher declared = Pattern.compile("\\b" + name + "\\s*=").matcher(source);
            assertThat(declared.find()).as("SmsPreparer declares %s", name).isTrue();

            StringBuilder value = new StringBuilder();
            for (int i = declared.end(); source.charAt(i) != ';'; i++) {
                char c = source.charAt(i);
                if (c == '"') {
                    for (i++; source.charAt(i) != '"'; i++) {
                        char d = source.charAt(i);
                        if (d == '\\') {
                            char escaped = source.charAt(++i);
                            value.append(escaped == 'n' ? '\n' : escaped == 'r' ? '\r' : escaped);
                        } else {
                            value.append(d);
                        }
                    }
                } else if (Character.isJavaIdentifierStart(c)) {
                    int end = i;
                    while (Character.isJavaIdentifierPart(source.charAt(end))) {
                        end++;
                    }
                    value.append(stringConstant(source, source.substring(i, end)));
                    i = end - 1;
                }
            }
            return value.toString();
        }
    }
}
