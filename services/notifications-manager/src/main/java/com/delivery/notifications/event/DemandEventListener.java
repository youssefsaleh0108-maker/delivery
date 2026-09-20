package com.delivery.notifications.event;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Component;

import com.delivery.notifications.service.NotificationDispatchService;
import com.delivery.notifications.service.RecipientDirectory;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Turns "this shop's neighbours looked for things nobody nearby sells" into one message a week.
 *
 * <p>Product Service holds the search log and works out, per area and per week, which terms went
 * unanswered; it does not know a merchant's channels, their locale or what they have opted out of,
 * and it must not. So it raises {@code demand.digest.weekly} and this service does what it does for
 * every other message — the merchant's contacts, their preferences, the dedupe, the log row, the
 * deep link.
 *
 * <p><strong>Its own queue, bound to {@code demand.#}.</strong> Not the order queue next door: a
 * demand event carries no order snapshot, so {@link OrderEventListener} would have to recognise and
 * discard it, and a weekly burst of digests queued in front of order notifications would delay the
 * ones a customer is waiting on.
 *
 * <p><strong>Deduplicated on the merchant and the week</strong>, which is the same key Product
 * Service claims the send with. Two independent guards on one fact: a relay that delivers the event
 * twice, or a job re-run after a fix, still reaches the merchant once.
 *
 * <p><strong>Nothing about a customer arrives on this event, and nothing is invented here.</strong>
 * The counts it renders are bands ("about 10"), the place is a neighbourhood name, and there is no
 * field on the payload that could hold a person.
 */
@Component
public class DemandEventListener {

    private static final Logger log = LoggerFactory.getLogger(DemandEventListener.class);

    /** The one event type this queue has an audience for. */
    static final String DIGEST_WEEKLY = "demand.digest.weekly";

    private final NotificationDispatchService dispatch;
    private final RecipientDirectory recipients;
    private final ObjectMapper objectMapper;

    public DemandEventListener(NotificationDispatchService dispatch, RecipientDirectory recipients,
                               ObjectMapper objectMapper) {
        this.dispatch = dispatch;
        this.recipients = recipients;
        this.objectMapper = objectMapper;
    }

    @RabbitListener(queues = "${delivery.notifications.demand-events-queue:notifications.demand-events}")
    public void onDemandEvent(String payload,
                              @Header(name = "eventType", required = false) String headerEventType,
                              @Header(name = "amqp_receivedRoutingKey", required = false) String routingKey,
                              @Header(name = "amqp_correlationId", required = false) String correlationId) {

        String eventType = headerEventType != null ? headerEventType : routingKey;

        if (correlationId != null) {
            MDC.put("correlationId", correlationId);
        }

        try {
            if (!DIGEST_WEEKLY.equals(eventType)) {
                // The binding is a wildcard so a second demand event reaches this service without a
                // config change; until one has an audience there is nothing to do with it.
                log.debug("No audience defined for {}", eventType);
                return;
            }

            JsonNode event = objectMapper.readTree(payload);
            String merchantId = textOrNull(event, "merchantId");
            String weekStart = textOrNull(event, "weekStart");
            List<JsonNode> terms = termsOf(event);

            // Acked rather than requeued: none of this is retryable, and an event that can never be
            // understood coming back for ever blocks every good one behind it.
            if (merchantId == null || weekStart == null || terms.isEmpty()) {
                log.warn("Ignoring a {} with no merchant, no week or no terms", eventType);
                return;
            }

            // The merchant and the week, which is the key Product Service claimed the send with.
            String dedupeKey = merchantId + ':' + weekStart;
            dispatch.dispatch(eventType, null, merchantId, recipients.contactsFor(merchantId),
                    placeholders(event, terms), correlationId, dedupeKey);

            log.debug("Requested a weekly demand digest for merchant {} for the week of {}",
                    merchantId, weekStart);

        } catch (Exception e) {
            log.error("Could not turn a demand event into a notification: {}", payload, e);

        } finally {
            if (correlationId != null) {
                MDC.remove("correlationId");
            }
        }
    }

    /**
     * The values the digest templates interpolate.
     *
     * <p>{@code storeId} is here because the templates declare a {@code DEMAND} link target, which
     * reads its id from exactly that placeholder — so a tapped message opens that shop's radar
     * rather than a listing.
     *
     * <p>{@code about} is a band the sender already rounded. It is placed as it arrives and never
     * recomputed or sharpened here: the rounding is the platform's answer to "how many of my
     * neighbours", and a message is the furthest that answer ever travels.
     */
    private Map<String, String> placeholders(JsonNode event, List<JsonNode> terms) {
        Map<String, String> values = new LinkedHashMap<>();
        JsonNode first = terms.get(0);
        values.put("storeId", event.path("storeId").asText(""));
        values.put("first", first.path("term").asText(""));
        values.put("about", Integer.toString(first.path("about").asInt(0)));
        values.put("area", where(first, event));
        values.put("terms", joined(terms));
        values.put("count", Integer.toString(terms.size()));
        return values;
    }

    /**
     * Where to say this was: the area that asked, the shop's region when the register has no name for
     * it, and "your area" when it has neither. Never a coordinate.
     */
    private static String where(JsonNode first, JsonNode event) {
        String area = first.path("area").asText(null);
        if (area != null && !area.isBlank()) {
            return area;
        }
        String region = event.path("region").asText(null);
        return region != null && !region.isBlank() ? region : "your area";
    }

    /**
     * The terms as a list reads them: "nappies, basmati rice, nescafe".
     *
     * <p>Joined here rather than in the template, because a template is one string and this list is
     * one, two or three long. Commas and nothing else, deliberately: one values map serves every
     * locale's templates, so an English "and" would appear in the middle of the Arabic message, and
     * a comma separates a list in both languages. The words themselves are whatever the customers
     * typed, so an Arabic digest already carries Arabic words.
     */
    private static String joined(List<JsonNode> terms) {
        List<String> words = new ArrayList<>();
        for (JsonNode term : terms) {
            String word = term.path("term").asText("").trim();
            if (!word.isEmpty()) {
                words.add(word);
            }
        }
        return String.join(", ", words);
    }

    private static List<JsonNode> termsOf(JsonNode event) {
        List<JsonNode> terms = new ArrayList<>();
        JsonNode node = event.path("terms");
        if (node.isArray()) {
            node.forEach(term -> {
                if (!term.path("term").asText("").isBlank()) {
                    terms.add(term);
                }
            });
        }
        return terms;
    }

    private static String textOrNull(JsonNode event, String field) {
        JsonNode node = event.path(field);
        if (node.isMissingNode() || node.isNull()) {
            return null;
        }
        String value = node.asText(null);
        return value == null || value.isBlank() ? null : value;
    }
}
