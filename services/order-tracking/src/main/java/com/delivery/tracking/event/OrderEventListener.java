package com.delivery.tracking.event;

import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.route.GeoPoint;
import com.delivery.tracking.service.PresenceService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Consumes {@code order.*} events off the bus and maintains the local participants projection.
 *
 * <p>This is the first consumer of the outbox-backed bus in the platform, and it is what makes the
 * live-tracking authorisation check a local row lookup instead of a synchronous call to Order
 * Manager on every poll.
 *
 * <p><strong>Delivery is at-least-once</strong>, so this handler must be idempotent - the outbox
 * relay republishes anything whose PUBLISHED flag failed to commit. Every event carries a full
 * order snapshot rather than a diff, so re-applying one is a no-op by construction: the projection
 * is overwritten with the same values.
 */
@Component
public class OrderEventListener {

    private static final Logger log = LoggerFactory.getLogger(OrderEventListener.class);

    private final OrderParticipantsRepository participants;
    private final PresenceService presence;
    private final ObjectMapper objectMapper;

    public OrderEventListener(OrderParticipantsRepository participants,
                              PresenceService presence,
                              ObjectMapper objectMapper) {
        this.participants = participants;
        this.presence = presence;
        this.objectMapper = objectMapper;
    }

    @RabbitListener(queues = "${delivery.tracking.order-events-queue:tracking.order-events}")
    @Transactional
    public void onOrderEvent(String payload,
                             @Header(name = "amqp_correlationId", required = false) String correlationId) {

        // Rejoins this work to the request that caused it. Without it the projection update is the
        // one hop in an order's life that cannot be found by correlation id, which is exactly the
        // gap Section 10's tracing requirement exists to close - and it was missing until the
        // Phase 5 review went looking for it.
        if (correlationId != null) {
            MDC.put(CORRELATION_MDC_KEY, correlationId);
        }

        try {
            JsonNode node = objectMapper.readTree(payload);

            UUID orderId = UUID.fromString(node.path("orderId").asText());
            String customerId = node.path("customerId").asText(null);
            String merchantId = node.path("merchantId").asText(null);
            String riderId = node.path("riderId").isNull() ? null : node.path("riderId").asText(null);
            String status = node.path("status").asText(null);

            if (customerId == null || merchantId == null || status == null) {
                // Not an order snapshot we recognise. Ack it anyway - rejecting would requeue it
                // forever and stall the whole queue behind one bad message.
                log.warn("Ignoring order event without the expected fields: {}", payload);
                return;
            }

            UUID carrierId = uuidOrNull(node, "deliveryProviderId");
            GeoPoint pickup = pointOrNull(node, "pickupLat", "pickupLng");
            GeoPoint dropoff = pointOrNull(node, "dropoffLat", "dropoffLng");

            OrderParticipants order = participants.findById(orderId)
                    .map(existing -> {
                        existing.apply(riderId, status);
                        return existing;
                    })
                    .orElseGet(() -> participants.save(new OrderParticipants(
                            orderId, customerId, merchantId, riderId, status)));
            order.applyRoute(carrierId, pickup, dropoff);

            // Which fleet a rider carries for, inferred from an order that names both. The weakest
            // of the two sources this service has - see CarrierMembership.Source - and the only one
            // that exists until a membership event does, which is why the inference is made here
            // rather than left as a gap the carrier console falls into.
            if (riderId != null && carrierId != null) {
                presence.learnCarrier(riderId, carrierId);
            }

            log.debug("Projection updated: order {} status {} rider {}", orderId, status, riderId);

        } catch (Exception e) {
            // Same reasoning: a malformed message must not become a poison pill. The DLQ on the
            // publishing side is where genuinely undeliverable events end up (Section 10).
            log.error("Could not apply order event, skipping: {}", payload, e);

        } finally {
            if (correlationId != null) {
                MDC.remove(CORRELATION_MDC_KEY);
            }
        }
    }

    /**
     * A UUID field, or null if it is absent, null or unparseable.
     *
     * <p>Unparseable is treated as absent rather than as a reason to reject the whole message. The
     * carrier id is a nice-to-have on this projection; the customer and rider ids that authorise
     * the tracking read path are not, and dropping an event because one optional field was
     * malformed would blind the map to protect a console filter.
     */
    private static UUID uuidOrNull(JsonNode node, String field) {
        JsonNode value = node.path(field);
        if (value.isMissingNode() || value.isNull()) {
            return null;
        }
        try {
            return UUID.fromString(value.asText());
        } catch (IllegalArgumentException e) {
            log.warn("Ignoring unparseable {} on an order event", field);
            return null;
        }
    }

    /**
     * A coordinate pair, or null if the event does not carry one.
     *
     * <p>Order Manager does not publish these yet - it sends a postal address and no lat/lng - so
     * today this is always null and the ETA endpoint says NO_DESTINATION. The projection is written
     * to accept them now so that the day the contract lands, no consumer change is needed. The
     * requested field names are pickupLat/pickupLng/dropoffLat/dropoffLng on the order snapshot.
     *
     * <p>Out-of-range values are dropped rather than stored. A message is untrusted input, and a
     * transposed pair would otherwise be projected, pass the database CHECK on each column
     * individually, and produce an ETA to the wrong hemisphere with no error anywhere.
     */
    private static GeoPoint pointOrNull(JsonNode node, String latField, String lngField) {
        JsonNode lat = node.path(latField);
        JsonNode lng = node.path(lngField);
        if (!lat.isNumber() || !lng.isNumber()) {
            return null;
        }
        try {
            return GeoPoint.of(lat.asDouble(), lng.asDouble()).orElse(null);
        } catch (IllegalArgumentException e) {
            log.warn("Ignoring out-of-range {}/{} on an order event", latField, lngField);
            return null;
        }
    }

    /** Matches the key platform-observability's filter uses on the HTTP side. */
    private static final String CORRELATION_MDC_KEY = "correlationId";
}
