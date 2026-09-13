package com.delivery.tracking.event;

import java.math.BigDecimal;
import java.time.DateTimeException;
import java.time.Instant;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Component;

import com.delivery.tracking.service.MembershipPeriodRecorder;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Consumes Order Manager's {@code carrier.member_joined} and {@code carrier.member_left} events —
 * when a rider joined or left a delivery company's fleet — into
 * {@code carrier_membership_periods}.
 *
 * <p>The payload is {@code {riderRef, providerId, change, at}}; {@code at} is the instant of the
 * change, as an ISO-8601 string (or epoch seconds, should a publisher ever write it that way).
 * Everything that makes a repeat or a late arrival harmless lives in
 * {@link MembershipPeriodRecorder}.
 *
 * <p>A payload this service cannot read is logged and acknowledged rather than requeued: requeued,
 * it would sit at the head of the queue forever. A failure to <em>store</em> one is not swallowed —
 * it propagates, so the broker redelivers it instead of the period silently going missing.
 */
@Component
public class CarrierMembershipEventListener {

    private static final Logger log = LoggerFactory.getLogger(CarrierMembershipEventListener.class);

    static final String JOINED = "carrier.member_joined";
    static final String LEFT = "carrier.member_left";

    private final MembershipPeriodRecorder recorder;
    private final ObjectMapper objectMapper;

    public CarrierMembershipEventListener(MembershipPeriodRecorder recorder,
                                          ObjectMapper objectMapper) {
        this.recorder = recorder;
        this.objectMapper = objectMapper;
    }

    @RabbitListener(queues = "${delivery.tracking.membership-events-queue:tracking.carrier-membership}")
    public void onMembershipEvent(String payload,
                                  @Header(name = "eventType", required = false) String eventType) {
        MembershipChange change;
        try {
            change = parse(objectMapper, payload, eventType);
        } catch (JsonProcessingException | IllegalArgumentException | DateTimeException e) {
            log.error("Ignoring a membership event this service cannot read: {}", payload, e);
            return;
        }

        switch (change.kind()) {
            case JOINED -> recorder.joined(change.riderId(), change.carrierId(), change.at());
            case LEFT -> recorder.left(change.riderId(), change.carrierId(), change.at());
        }
    }

    /**
     * Reads one event. The payload's own {@code change} decides which it is; the {@code eventType}
     * header the outbox relay sets is the fallback for a payload without one.
     *
     * @throws IllegalArgumentException for a payload missing what a membership change needs
     */
    static MembershipChange parse(ObjectMapper json, String payload, String eventType)
            throws JsonProcessingException {
        JsonNode node = json.readTree(payload);
        String riderId = node.path("riderRef").asText(null);
        String providerId = node.path("providerId").asText(null);
        String change = node.path("change").asText(null);
        JsonNode at = node.get("at");

        if (change == null && eventType != null) {
            change = JOINED.equals(eventType) ? "JOINED" : LEFT.equals(eventType) ? "LEFT" : null;
        }
        if (riderId == null || riderId.isBlank() || providerId == null || change == null
                || at == null || at.isNull()) {
            throw new IllegalArgumentException("Not a membership change this service recognises");
        }
        return new MembershipChange(MembershipChange.Kind.valueOf(change), riderId,
                UUID.fromString(providerId), instantOf(at));
    }

    /** ISO-8601 text, or epoch seconds with a fraction — the two ways Jackson writes an Instant. */
    static Instant instantOf(JsonNode at) {
        if (at.isNumber()) {
            BigDecimal seconds = at.decimalValue();
            long whole = seconds.longValue();
            int nanos = seconds.subtract(BigDecimal.valueOf(whole)).movePointRight(9).intValue();
            return Instant.ofEpochSecond(whole, nanos);
        }
        return Instant.parse(at.asText());
    }

    /** One rider joining or leaving one fleet, at one instant. */
    record MembershipChange(Kind kind, String riderId, UUID carrierId, Instant at) {
        enum Kind { JOINED, LEFT }
    }
}
