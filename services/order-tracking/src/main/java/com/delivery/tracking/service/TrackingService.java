package com.delivery.tracking.service;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.domain.TrackingEvent;
import com.delivery.tracking.domain.TrackingEventRepository;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Rider location: high-volume writes to Postgres, hot reads from Redis (Section 10).
 *
 * <p>The split matters. Every active rider pings every few seconds and every customer watching a
 * map polls at a similar rate, so serving "where is my rider right now" from Postgres would put the
 * busiest read in the platform on the same table taking the busiest write. Redis holds only the
 * latest position per order; Postgres keeps the full history for replay and disputes.
 */
@Service
public class TrackingService {

    private static final Logger log = LoggerFactory.getLogger(TrackingService.class);
    private static final String KEY_PREFIX = "delivery:tracking:order:";

    private final TrackingEventRepository events;
    private final OrderParticipantsRepository participants;
    private final PresenceService presence;
    private final StringRedisTemplate redis;
    private final ObjectMapper objectMapper;
    private final Duration cacheTtl;

    public TrackingService(TrackingEventRepository events,
                           OrderParticipantsRepository participants,
                           PresenceService presence,
                           StringRedisTemplate redis,
                           ObjectMapper objectMapper,
                           @Value("${delivery.tracking.location-cache-ttl:60s}") Duration cacheTtl) {
        this.events = events;
        this.participants = participants;
        this.presence = presence;
        this.redis = redis;
        this.objectMapper = objectMapper;
        this.cacheTtl = cacheTtl;
    }

    /**
     * Records a ping from a rider.
     *
     * <p>The rider must be the one assigned to the order - otherwise any rider could write a
     * position onto someone else's delivery, and the customer's map would show a stranger.
     */
    @Transactional
    public Position ping(UUID orderId, String riderId, double lat, double lng, Float accuracyM) {
        OrderParticipants order = participants.findById(orderId)
                .orElseThrow(() -> new TrackingNotFoundException(orderId));

        if (!riderId.equals(order.getRiderId())) {
            // 404, not 403: a rider probing order ids should not learn which ones exist.
            throw new TrackingNotFoundException(orderId);
        }

        events.save(new TrackingEvent(orderId, riderId, lat, lng, accuracyM));

        // A ping on an order is evidence that this rider's phone is alive, so it counts as presence
        // too. Without this a rider would drop off the on-duty roster the moment they picked
        // something up — the roster would show only the riders with nothing to do, which is exactly
        // backwards for a dispatcher watching a fleet.
        presence.recordFix(riderId, lat, lng, accuracyM);

        Position position = new Position(orderId, riderId, lat, lng, accuracyM, Instant.now());
        cache(position);
        return position;
    }

    /**
     * The live read path. Redis first; Postgres only on a miss (a restart, or an eviction).
     */
    @Transactional(readOnly = true)
    public Optional<Position> currentPosition(UUID orderId, String userId, boolean isBackoffice) {
        OrderParticipants order = participants.findById(orderId)
                .orElseThrow(() -> new TrackingNotFoundException(orderId));

        if (!isBackoffice && !order.isVisibleTo(userId)) {
            throw new TrackingNotFoundException(orderId);
        }

        String cached = redis.opsForValue().get(KEY_PREFIX + orderId);
        if (cached != null) {
            try {
                return Optional.of(objectMapper.readValue(cached, Position.class));
            } catch (JsonProcessingException e) {
                // A corrupt cache entry must not break the screen; fall through to Postgres.
                log.warn("Discarding unreadable cached position for order {}", orderId, e);
                redis.delete(KEY_PREFIX + orderId);
            }
        }

        List<TrackingEvent> latest = events.findLatestForOrder(orderId, PageRequest.of(0, 1));
        if (latest.isEmpty()) {
            return Optional.empty();
        }

        TrackingEvent event = latest.get(0);
        Position position = new Position(orderId, event.getRiderId(), event.getLat(),
                event.getLng(), event.getAccuracyM(), event.getRecordedAt());
        cache(position);
        return Optional.of(position);
    }

    /** The full breadcrumb trail, for replaying a delivery or investigating a dispute. */
    @Transactional(readOnly = true)
    public List<Position> history(UUID orderId, String userId, boolean isBackoffice) {
        OrderParticipants order = participants.findById(orderId)
                .orElseThrow(() -> new TrackingNotFoundException(orderId));

        if (!isBackoffice && !order.isVisibleTo(userId)) {
            throw new TrackingNotFoundException(orderId);
        }

        return events.findByOrderIdOrderByRecordedAtAsc(orderId).stream()
                .map(e -> new Position(orderId, e.getRiderId(), e.getLat(), e.getLng(),
                        e.getAccuracyM(), e.getRecordedAt()))
                .toList();
    }

    @Transactional(readOnly = true)
    public Optional<OrderParticipants> participantsOf(UUID orderId) {
        return participants.findById(orderId);
    }

    private void cache(Position position) {
        try {
            redis.opsForValue().set(
                    KEY_PREFIX + position.orderId(),
                    objectMapper.writeValueAsString(position),
                    cacheTtl);
        } catch (Exception e) {
            // Redis being down degrades reads to Postgres; it must never fail a rider's ping,
            // because losing the write would lose the position permanently.
            log.warn("Could not cache position for order {}", position.orderId(), e);
        }
    }

    public record Position(
            UUID orderId,
            String riderId,
            double lat,
            double lng,
            Float accuracyM,
            Instant recordedAt) {
    }

    public static class TrackingNotFoundException extends RuntimeException {
        public TrackingNotFoundException(UUID orderId) {
            super("No tracking information for order " + orderId);
        }
    }
}
