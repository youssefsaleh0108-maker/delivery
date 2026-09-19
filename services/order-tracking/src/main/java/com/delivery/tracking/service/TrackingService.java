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
import com.delivery.tracking.route.GeoPoint;
import com.delivery.tracking.route.HaversineRouteProvider;
import com.delivery.tracking.service.PresenceService.LatestFix;
import com.delivery.tracking.service.RiderSighting.State;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Rider location: high-volume writes to Postgres, hot reads from Redis (Section 10), and who may
 * see which of it.
 *
 * <p>The split matters. Every active rider pings every few seconds and every customer watching a
 * map polls at a similar rate, so serving "where is my rider right now" from Postgres would put the
 * busiest read in the platform on the same table taking the busiest write. Redis holds only the
 * latest position per order and per rider; Postgres keeps the trail for replay and disputes.
 *
 * <h2>Who sees the rider</h2>
 *
 * <p>Real positions made the old rule — "anyone on the order sees everything on it" — wrong in
 * three ways at once: a READY order's trail started at the claim, which is often the rider's home;
 * a rider carrying two customers' orders showed each customer the way to the other's door; and the
 * shop kept watching the rider long after the bag had left. One method now decides every
 * order-scoped read for everybody but the back office, {@link #sightingFor}, and the trail and the
 * live topic follow it; the rules are written out there.
 */
@Service
public class TrackingService {

    private static final Logger log = LoggerFactory.getLogger(TrackingService.class);
    private static final String KEY_PREFIX = "delivery:tracking:order:";

    /**
     * Within this of the door of another customer's order that the rider holds, or finished
     * recently, the rider is not shown to this order's customer or shop. Hand-over is where the
     * rider stands still at somebody's door, and the first fixes after the rider's next leg starts
     * are still there.
     */
    static final double HANDOVER_BUFFER_M = 300;

    /** How long after another order finished its door still counts (see the buffer above). */
    static final Duration HANDOVER_WINDOW = Duration.ofMinutes(30);

    /**
     * Before pickup, the rider is shown to the customer and the shop only within this of the shop.
     * Claims often happen at home, and a dot there says where the rider lives.
     */
    static final double SHOP_RADIUS_M = 2_000;

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

    // -----------------------------------------------------------------------------------------
    // Writing
    // -----------------------------------------------------------------------------------------

    /**
     * Records a ping from a rider.
     *
     * <p>The rider must be the one assigned to the order - otherwise any rider could write a
     * position onto someone else's delivery, and the customer's map would show a stranger.
     *
     * <p>The order must also still be running. A handset that keeps pinging after hand-over is the
     * normal case rather than the rare one - the app is backgrounded, the queued pings drain - and
     * accepting them would follow the rider away from the customer's door on the customer's own
     * map.
     *
     * <p>Then the fix itself must be believable — precise enough, from now, from the service area,
     * and somewhere the rider could have got to ({@link FixPolicy}). That is judged after both
     * checks above, so a refusal's reason is only ever given to the rider already known to be on
     * the order, and before anything is written, so a refused fix never reaches the trail, the
     * cache or the live topic. A fix that is believable but adds nothing new — not newer than the
     * rider's last one, or too soon after it — is not written either, and comes back empty rather
     * than refused.
     *
     * <p><b>Only a collected order has a trail.</b> A fix on an order still READY moves the live
     * dot and nothing else: it is cached and may be pushed, and is never written to
     * {@code tracking_events}. A rider claims wherever they happen to be — often at home — and a
     * trail that starts there keeps that place for the whole retention window.
     *
     * @return what was recorded, or empty when there was nothing new to record
     * @throws FixPolicy.FixRejectedException when the fix is not believable
     */
    @Transactional
    public Optional<Recorded> ping(UUID orderId, String riderId, Fix fix) {
        OrderParticipants order = participants.findById(orderId)
                .orElseThrow(() -> new TrackingNotFoundException(orderId));

        if (!riderId.equals(order.getRiderId())) {
            // 404, not 403: a rider probing order ids should not learn which ones exist.
            throw new TrackingNotFoundException(orderId);
        }

        if (order.isComplete()) {
            // Checked after the rider match, so that the order's state is only ever observable by
            // the rider who is already known to be on it.
            throw new TrackingClosedException();
        }

        // A ping on an order is evidence that this rider's phone is alive, so it counts as presence
        // too. Without this a rider would drop off the on-duty roster the moment they picked
        // something up — the roster would show only the riders with nothing to do, which is exactly
        // backwards for a dispatcher watching a fleet. It is also where the fix is judged, against
        // the last one accepted for this rider on any order, so it goes first: a refusal here
        // throws before the trail below is written. And it remembers that the rider's latest fix
        // went on this order, which is what {@link #sightingFor} reads.
        Optional<Instant> recordedAt = presence.recordFix(riderId, fix, orderId);
        if (recordedAt.isEmpty()) {
            return Optional.empty();
        }
        Instant at = recordedAt.get();

        boolean onTrail = order.isCarrying();
        if (onTrail) {
            events.save(new TrackingEvent(orderId, riderId, fix.lat(), fix.lng(), fix.accuracyM(),
                    at));
        }

        Position position = new Position(orderId, riderId, fix.lat(), fix.lng(), fix.accuracyM(),
                at);
        cache(position);

        // The order's live topic reaches its customer, so it carries only what the customer may
        // see: the same rule as their reads, applied to the fix just recorded.
        LatestFix latest = new LatestFix(riderId, orderId, fix.lat(), fix.lng(), fix.accuracyM(),
                at);
        boolean live = judge(order, false, latest).state() == State.VISIBLE;
        return Optional.of(new Recorded(position, onTrail, live));
    }

    // -----------------------------------------------------------------------------------------
    // Who sees the rider
    // -----------------------------------------------------------------------------------------

    /**
     * What {@code callerId} may know, right now, of where {@code order}'s rider is — the one rule
     * behind every order-scoped read of a rider's position: the live position, the ETA, the trail
     * and the live topic, and any view built from them (a checkout's map).
     *
     * <p><b>The back office</b> sees the order's own latest position, as it always did. <b>The
     * rider</b> sees their own latest fix. For <b>the customer and the shop</b>, in this order:
     *
     * <ol>
     *   <li>A delivered or cancelled order shows nothing: {@link State#CLOSED}.</li>
     *   <li>The rider is shown only while their latest accepted fix went on this order — or, for the
     *       customer only, on another order of the same customer (a multi-shop checkout). A fix on
     *       another customer's order means the rider is on that delivery now:
     *       {@link State#ON_ANOTHER_DELIVERY}, which the shop also gets for a sibling order of the
     *       same customer, since a shop must not follow the rider to the customer's other shops. No
     *       fix yet, or a latest fix on no order at all: {@link State#NO_FIX}.</li>
     *   <li>Hand-over buffer: a position within {@value #HANDOVER_BUFFER_M} m of the door of
     *       another customer's order that the rider holds, or finished within
     *       {@link #HANDOVER_WINDOW} of that position's time, is withheld as
     *       {@link State#ON_ANOTHER_DELIVERY}. When the rider finishes B's delivery and the leg
     *       switches to A, the first fixes on A's order are still at B's door. The customer's own
     *       doors never count against them.</li>
     *   <li>The shop sees the rider only until pickup: once collected, {@link State#AFTER_PICKUP}
     *       (an estimate, but no position).</li>
     *   <li>Before pickup, the rider is shown only within {@value #SHOP_RADIUS_M} m of the shop;
     *       further away, or with no shop pin to measure against, {@link State#HEADING_TO_SHOP}
     *       (an estimate, but no position).</li>
     * </ol>
     *
     * <p>Anybody else is told the order does not exist.
     *
     * @throws TrackingNotFoundException when the caller is not on the order and not back office
     */
    @Transactional(readOnly = true)
    public RiderSighting sightingFor(OrderParticipants order, String callerId,
                                     boolean isBackoffice) {
        return switch (audienceOf(order, callerId, isBackoffice)) {
            case BACKOFFICE -> orderPosition(order.getOrderId())
                    .map(RiderSighting::visible)
                    .orElseGet(() -> RiderSighting.nothing(State.NO_FIX));
            case RIDER -> presence.latestFix(order.getRiderId())
                    .map(latest -> asPositionOn(order, latest))
                    .or(() -> orderPosition(order.getOrderId()))
                    .map(RiderSighting::visible)
                    .orElseGet(() -> RiderSighting.nothing(State.NO_FIX));
            case CUSTOMER -> judge(order, false, latestFixOf(order));
            case MERCHANT -> judge(order, true, latestFixOf(order));
        };
    }

    /**
     * "Where is my rider right now": the position {@link #sightingFor} lets the caller see, if any.
     */
    @Transactional(readOnly = true)
    public Optional<Position> currentPosition(UUID orderId, String userId, boolean isBackoffice) {
        OrderParticipants order = participants.findById(orderId)
                .orElseThrow(() -> new TrackingNotFoundException(orderId));
        return sightingFor(order, userId, isBackoffice).shown();
    }

    /** {@link #sightingFor}, for an order known only by its id. */
    @Transactional(readOnly = true)
    public RiderSighting sightingFor(UUID orderId, String userId, boolean isBackoffice) {
        OrderParticipants order = participants.findById(orderId)
                .orElseThrow(() -> new TrackingNotFoundException(orderId));
        return sightingFor(order, userId, isBackoffice);
    }

    /**
     * The breadcrumb trail, for replaying a delivery or investigating a dispute — and the line on
     * a customer's map.
     *
     * <p>The back office and the rider get all of it. The shop gets none: it sees the rider only
     * until pickup, and a trail only exists after it. The customer gets it only while the rider is
     * {@link State#VISIBLE} to them ({@link #sightingFor}), only while the order is collected and
     * not yet finished, only from the moment it was collected ({@code picked_up_at}), and without
     * the points inside the hand-over buffer of another customer's door. An order collected before
     * {@code picked_up_at} was recorded shows no trail: without the time there is no telling which
     * points came before it.
     */
    @Transactional(readOnly = true)
    public List<Position> history(UUID orderId, String userId, boolean isBackoffice) {
        OrderParticipants order = participants.findById(orderId)
                .orElseThrow(() -> new TrackingNotFoundException(orderId));

        return switch (audienceOf(order, userId, isBackoffice)) {
            case BACKOFFICE, RIDER -> events.findByOrderIdOrderByRecordedAtAsc(orderId).stream()
                    .map(e -> asPosition(orderId, e))
                    .toList();
            case MERCHANT -> List.of();
            case CUSTOMER -> customersTrail(order);
        };
    }

    /**
     * Whether this user, not being back office, may subscribe to the order's live topic: its
     * customer and its rider. Not the shop, which sees the rider only until pickup and could not be
     * unsubscribed at it; it reads the position instead, which follows the rule on every request.
     * What the topic carries is filtered for the customer when each fix is recorded ({@link #ping}).
     */
    public static boolean mayWatchLive(OrderParticipants order, String userId) {
        return userId.equals(order.getCustomerId()) || userId.equals(order.getRiderId());
    }

    @Transactional(readOnly = true)
    public Optional<OrderParticipants> participantsOf(UUID orderId) {
        return participants.findById(orderId);
    }

    /** The rule of {@link #sightingFor} for the customer ({@code forShop} false) or the shop. */
    RiderSighting judge(OrderParticipants order, boolean forShop, LatestFix latest) {
        if (order.isComplete()) {
            return RiderSighting.nothing(State.CLOSED);
        }
        String riderId = order.getRiderId();
        if (riderId == null || latest == null || !riderId.equals(latest.riderId())
                || latest.orderId() == null) {
            return RiderSighting.nothing(State.NO_FIX);
        }
        if (!latest.orderId().equals(order.getOrderId())) {
            Optional<OrderParticipants> onOrder = participants.findById(latest.orderId());
            if (onOrder.isEmpty() || !riderId.equals(onOrder.get().getRiderId())) {
                return RiderSighting.nothing(State.NO_FIX);
            }
            boolean sameCustomer = order.getCustomerId().equals(onOrder.get().getCustomerId());
            if (forShop || !sameCustomer) {
                return RiderSighting.nothing(State.ON_ANOTHER_DELIVERY);
            }
        }

        Position position = asPositionOn(order, latest);
        List<OrderParticipants> doors = participants.otherCustomersDoors(riderId,
                order.getCustomerId(), position.recordedAt().minus(HANDOVER_WINDOW));
        if (nearAnotherCustomersDoor(position.lat(), position.lng(), position.recordedAt(),
                doors)) {
            return RiderSighting.nothing(State.ON_ANOTHER_DELIVERY);
        }

        if (forShop && order.isCarrying()) {
            return RiderSighting.timedOnly(State.AFTER_PICKUP, position);
        }
        if (!order.isCarrying()) {
            Optional<GeoPoint> shop = order.pickup();
            if (shop.isEmpty() || HaversineRouteProvider.distanceMetres(shop.get(),
                    new GeoPoint(position.lat(), position.lng())) > SHOP_RADIUS_M) {
                return RiderSighting.timedOnly(State.HEADING_TO_SHOP, position);
            }
        }
        return RiderSighting.visible(position);
    }

    private List<Position> customersTrail(OrderParticipants order) {
        Instant collectedAt = order.getPickedUpAt();
        if (!order.isCarrying() || collectedAt == null) {
            return List.of();
        }
        if (judge(order, false, latestFixOf(order)).state() != State.VISIBLE) {
            return List.of();
        }
        List<OrderParticipants> doors = participants.otherCustomersDoors(order.getRiderId(),
                order.getCustomerId(), collectedAt.minus(HANDOVER_WINDOW));
        return events.findByOrderIdAndRecordedAtGreaterThanEqualOrderByRecordedAtAsc(
                        order.getOrderId(), collectedAt).stream()
                .filter(e -> !nearAnotherCustomersDoor(e.getLat(), e.getLng(), e.getRecordedAt(),
                        doors))
                .map(e -> asPosition(order.getOrderId(), e))
                .toList();
    }

    /**
     * Whether a point taken at {@code at} lies within the hand-over buffer of one of these doors:
     * an order still in the rider's hands, or one finished no more than {@link #HANDOVER_WINDOW}
     * before the point was taken. Judged against the point's own time rather than the reader's, so
     * a dot left at a door by a phone that has since gone quiet stays withheld, and a trail point
     * recorded at a hand-over stays out of the trail for good.
     */
    private static boolean nearAnotherCustomersDoor(double lat, double lng, Instant at,
                                                    List<OrderParticipants> doors) {
        GeoPoint point = new GeoPoint(lat, lng);
        for (OrderParticipants other : doors) {
            Optional<GeoPoint> door = other.dropoff();
            if (door.isEmpty()
                    || HaversineRouteProvider.distanceMetres(point, door.get()) > HANDOVER_BUFFER_M) {
                continue;
            }
            Instant finished = other.getCompletedAt();
            if (!other.isComplete() || finished == null
                    || !at.isAfter(finished.plus(HANDOVER_WINDOW))) {
                return true;
            }
        }
        return false;
    }

    private LatestFix latestFixOf(OrderParticipants order) {
        return presence.latestFix(order.getRiderId()).orElse(null);
    }

    private static Position asPositionOn(OrderParticipants order, LatestFix latest) {
        return new Position(order.getOrderId(), latest.riderId(), latest.lat(), latest.lng(),
                latest.accuracyM(), latest.at());
    }

    private static Position asPosition(UUID orderId, TrackingEvent e) {
        return new Position(orderId, e.getRiderId(), e.getLat(), e.getLng(), e.getAccuracyM(),
                e.getRecordedAt());
    }

    private enum Audience { BACKOFFICE, RIDER, CUSTOMER, MERCHANT }

    /**
     * Who the caller is to this order. The rider first (their own position), then the customer —
     * a shop ordering from itself is that order's customer — then the shop.
     */
    private static Audience audienceOf(OrderParticipants order, String callerId,
                                       boolean isBackoffice) {
        if (isBackoffice) {
            return Audience.BACKOFFICE;
        }
        if (callerId != null) {
            if (callerId.equals(order.getRiderId())) {
                return Audience.RIDER;
            }
            if (callerId.equals(order.getCustomerId())) {
                return Audience.CUSTOMER;
            }
            if (callerId.equals(order.getMerchantId())) {
                return Audience.MERCHANT;
            }
        }
        throw new TrackingNotFoundException(order.getOrderId());
    }

    // -----------------------------------------------------------------------------------------
    // The order's own latest position: Redis first, Postgres on a miss
    // -----------------------------------------------------------------------------------------

    /**
     * The latest position reported on this order, whatever it was. Redis first; Postgres only on
     * a miss (a restart, or an eviction). What the back office reads, unchanged.
     */
    private Optional<Position> orderPosition(UUID orderId) {
        String cached = null;
        try {
            cached = redis.opsForValue().get(KEY_PREFIX + orderId);
        } catch (Exception e) {
            log.warn("Could not read the cached position for order {}", orderId, e);
        }
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

        Position position = asPosition(orderId, latest.get(0));
        cache(position);
        return Optional.of(position);
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

    /**
     * What a ping recorded.
     *
     * @param position the position as recorded
     * @param onTrail  whether it went on the trail — false for an order not yet collected, whose
     *                 fixes move the live dot only
     * @param live     whether the order's live topic may carry it: whether the order's customer
     *                 may see it (see {@link #sightingFor})
     */
    public record Recorded(Position position, boolean onTrail, boolean live) {
    }

    public static class TrackingNotFoundException extends RuntimeException {
        public TrackingNotFoundException(UUID orderId) {
            super("No tracking information for order " + orderId);
        }
    }

    /**
     * A ping on a delivery that has already finished.
     *
     * <p>Deliberately not a "not found": the caller is the assigned rider and already knows the
     * order exists, so answering 404 would tell them their own delivery had vanished and invite the
     * app to retry it forever.
     */
    public static class TrackingClosedException extends RuntimeException {
        public TrackingClosedException() {
            super("This delivery is complete; positions are no longer recorded for it");
        }
    }
}
