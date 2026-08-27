package com.delivery.tracking.service;

import java.time.Duration;
import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.tracking.domain.CarrierMembership;
import com.delivery.tracking.domain.CarrierMembershipRepository;
import com.delivery.tracking.domain.DutyState;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.domain.PresenceState;
import com.delivery.tracking.domain.RiderDutyEvent;
import com.delivery.tracking.domain.RiderDutyEventRepository;
import com.delivery.tracking.domain.RiderPresence;
import com.delivery.tracking.domain.RiderPresenceRepository;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Rider duty, rider presence, and where a rider is when they are carrying nothing.
 *
 * <p>Three questions the platform could not answer before: is this rider working, is their phone
 * still talking to us, and where are they right now. The design's carrier and backoffice consoles
 * are built on all three, and the rider roster on a map needs the third even for a rider who holds
 * no job — which is why location here is not scoped to an order the way {@link TrackingService} is.
 *
 * <h2>Why Postgres and Redis, and which one is the record</h2>
 *
 * <p>Postgres is the record. A single row per rider, updated in place, holding the declared duty
 * state and the last known fix. Redis holds the same snapshot under a TTL for the hot read. That
 * order matters and the obvious alternative — presence living purely in Redis with a TTL, which is
 * the usual shape for this — was rejected: a cache flush or a Redis restart would take the entire
 * fleet off duty simultaneously, including riders halfway through a delivery, and nothing would be
 * able to tell that from every rider genuinely going home. The durable row means a restart costs a
 * slow first read and nothing else.
 *
 * <p>What Redis does buy is the write throttle. A rider pings every few seconds, and moving the
 * durable row on every one of them would double the cost of the busiest write path in the platform
 * for no benefit — nobody needs {@code last_seen_at} accurate to the second in Postgres. So the
 * warm path writes Redis every time and Postgres at most once per
 * {@code delivery.tracking.presence.persist-interval}. With Redis unavailable, every ping takes the
 * cold path and writes the row: slower, and correct, which is the right way round.
 *
 * <h2>Why the TTL is not the answer on its own</h2>
 *
 * <p>Freshness is computed from {@code last_seen_at} at read time, in
 * {@link RiderPresence#effectiveState}, rather than being inferred from a Redis key having expired.
 * A cached snapshot therefore cannot claim to be fresh just because it is still in the cache, and
 * the roster — which is read from Postgres, where there is no TTL at all — applies exactly the same
 * rule. One definition of "on duty", in one place, whichever store answered.
 */
@Service
public class PresenceService {

    private static final Logger log = LoggerFactory.getLogger(PresenceService.class);
    private static final String KEY_PREFIX = "delivery:tracking:presence:";

    private final RiderPresenceRepository presence;
    private final RiderDutyEventRepository dutyEvents;
    private final CarrierMembershipRepository memberships;
    private final OrderParticipantsRepository participants;
    private final StringRedisTemplate redis;
    private final ObjectMapper objectMapper;
    private final Duration presenceWindow;
    private final Duration persistInterval;

    public PresenceService(RiderPresenceRepository presence,
                           RiderDutyEventRepository dutyEvents,
                           CarrierMembershipRepository memberships,
                           OrderParticipantsRepository participants,
                           StringRedisTemplate redis,
                           ObjectMapper objectMapper,
                           @Value("${delivery.tracking.presence.ttl:120s}") Duration presenceWindow,
                           @Value("${delivery.tracking.presence.persist-interval:30s}") Duration persistInterval) {
        this.presence = presence;
        this.dutyEvents = dutyEvents;
        this.memberships = memberships;
        this.participants = participants;
        this.redis = redis;
        this.objectMapper = objectMapper;
        this.presenceWindow = presenceWindow;
        this.persistInterval = persistInterval;
    }

    // -----------------------------------------------------------------------------------------
    // Writing
    // -----------------------------------------------------------------------------------------

    /**
     * A rider declares themselves on or off duty.
     *
     * <p>Only ever called with a rider id taken from the access token, never from the request body
     * — a rider putting somebody else on duty is not a request this service can be asked to make.
     *
     * <p>Note that going on duty does not fabricate a fix. A rider who taps "go online" with no GPS
     * yet reads as {@link PresenceState#STALE}, not {@link PresenceState#ON_DUTY}, because there is
     * no evidence their phone is anywhere.
     */
    @Transactional
    public RiderPresenceView declare(String riderId, DutyState state, RiderDutyEvent.Source source) {
        Instant now = Instant.now();

        RiderPresence row = presence.findById(riderId)
                .orElseGet(() -> RiderPresence.firstSeen(riderId, now));

        boolean transition = row.getDutyState() != state;
        row.declare(state, now);
        presence.save(row);

        if (transition) {
            // Only real transitions are logged. An app that re-asserts duty every time it comes to
            // the foreground would otherwise write a row a minute and turn the shift log into noise
            // exactly when somebody is trying to read it.
            dutyEvents.save(new RiderDutyEvent(riderId, state, source, now));
        }

        cache(PresenceSnapshot.of(row));
        return RiderPresenceView.of(row, now, presenceWindow);
    }

    /**
     * Records a fix for a rider, whether or not they are carrying anything.
     *
     * <p>Called from the off-order ping endpoint and from {@link TrackingService#ping} — an order
     * ping is evidence of life too, and a rider mid-delivery who did not count as present would
     * drop off the roster the moment they picked something up.
     *
     * <p>Never changes duty state. A location is evidence that a phone is alive, not consent to be
     * given work.
     */
    @Transactional
    public void recordFix(String riderId, double lat, double lng, Float accuracyM) {
        Instant now = Instant.now();

        PresenceSnapshot cached = readCache(riderId);
        if (cached == null) {
            // Cold: either this rider is new, or Redis has forgotten them (eviction, restart, or
            // Redis being down entirely). Settle it against the record and write through.
            RiderPresence row = presence.findById(riderId)
                    .orElseGet(() -> RiderPresence.firstSeen(riderId, now));
            row.sighted(lat, lng, accuracyM, now);
            presence.save(row);
            cache(PresenceSnapshot.of(row));
            return;
        }

        // Warm: a cached snapshot exists, so the durable row does too. Move it only if the throttle
        // is due — see RiderPresenceRepository#touchIfDue for what this trades away and why.
        presence.touchIfDue(riderId, lat, lng, accuracyM, now, now.minus(persistInterval));
        cache(cached.withFix(lat, lng, accuracyM, now));
    }

    /**
     * Records that a rider carries for a fleet, learned from an order event.
     *
     * <p>An inference rather than a fact — see {@link CarrierMembership.Source#ORDER_EVENT} — and
     * it is what lets a carrier console see its own riders before the membership contract exists.
     * It creates an off-duty presence row for a rider we have never heard from, so a fleet's roster
     * shows "hired, not working" rather than an empty list that looks like a broken screen.
     */
    @Transactional
    public void learnCarrier(String riderId, UUID carrierId) {
        if (riderId == null || carrierId == null) {
            return;
        }
        Instant now = Instant.now();

        memberships.findById(riderId).ifPresentOrElse(
                existing -> existing.apply(carrierId, CarrierMembership.Kind.RIDER,
                        CarrierMembership.Source.ORDER_EVENT),
                () -> memberships.save(new CarrierMembership(riderId, carrierId,
                        CarrierMembership.Kind.RIDER, CarrierMembership.Source.ORDER_EVENT)));

        RiderPresence row = presence.findById(riderId)
                .orElseGet(() -> RiderPresence.firstSeen(riderId, now));
        row.attachCarrier(carrierId, now);
        presence.save(row);
    }

    // -----------------------------------------------------------------------------------------
    // Reading
    // -----------------------------------------------------------------------------------------

    /** A rider's own view of their state. No authorisation question: it is theirs. */
    @Transactional(readOnly = true)
    public Optional<RiderPresenceView> ownPresence(String riderId) {
        Instant now = Instant.now();
        PresenceSnapshot cached = readCache(riderId);
        if (cached != null) {
            return Optional.of(cached.toView(now, presenceWindow));
        }
        return presence.findById(riderId).map(row -> RiderPresenceView.of(row, now, presenceWindow));
    }

    /**
     * Where a rider is, for someone who is not that rider.
     *
     * <p>Four callers may ask, and the list is deliberately short, because a rider's live position
     * is personal data about a worker rather than a property of an order:
     *
     * <ul>
     *   <li>the rider themselves;</li>
     *   <li>backoffice, which is what the support role is for;</li>
     *   <li>the fleet that employs them — their own dispatcher, and nobody else's;</li>
     *   <li>a customer with a live order in that rider's hands, and only while it is live.</li>
     * </ul>
     *
     * <p>The merchant is <em>not</em> on that list, although they can see the same rider through
     * {@code GET /api/tracking/orders/{id}}. The difference is the scope: the order-scoped read is
     * bounded by one delivery, while this one follows a person, and a shop has no business
     * following a courier once the bag has left the counter.
     *
     * <p>A caller who is none of these gets the same {@code not found} as a caller asking about a
     * rider id that does not exist. 403 would confirm the rider is real, which is enough to let
     * somebody enumerate the fleet.
     */
    @Transactional(readOnly = true)
    public RiderPresenceView locationOf(String riderId, String callerId, boolean isBackoffice) {
        if (!mayRead(riderId, callerId, isBackoffice)) {
            throw new PresenceNotFoundException(riderId);
        }
        return ownPresence(riderId).orElseThrow(() -> new PresenceNotFoundException(riderId));
    }

    private boolean mayRead(String riderId, String callerId, boolean isBackoffice) {
        if (callerId.equals(riderId) || isBackoffice) {
            return true;
        }
        Optional<UUID> callerCarrier = carrierOf(callerId);
        if (callerCarrier.isPresent() && callerCarrier.equals(carrierOf(riderId))) {
            return true;
        }
        return participants.customerHasLiveOrderWith(callerId, riderId);
    }

    /**
     * The roster a console polls: who is out there, and when we last heard from them.
     *
     * <p>A carrier's scope is resolved from their own membership row and never accepted from the
     * request, the same rule Order Manager applies to a carrier's job list — a carrier cannot name
     * a company, so there is no request shape that reads a competitor's fleet. Backoffice may name
     * one, because seeing across fleets is the job.
     *
     * <p>Served from Postgres rather than by fanning out over Redis keys. The roster is a filtered,
     * sorted query over the whole fleet, which is what a relational index is for; doing it in Redis
     * would mean a key scan, and a key scan on the hot instance is how a cache becomes an outage.
     * The cost is that {@code last_seen_at} here lags the true value by up to the persist interval.
     */
    @Transactional(readOnly = true)
    public List<RiderPresenceView> roster(String callerId, boolean isBackoffice,
                                          UUID requestedCarrierId, boolean onDutyOnly) {
        Instant now = Instant.now();

        UUID scope;
        if (isBackoffice) {
            scope = requestedCarrierId;
        } else {
            scope = carrierOf(callerId).orElseThrow(() -> new NoCarrierException(
                    "You are not a member of any delivery company"));
        }

        List<RiderPresence> rows;
        if (scope == null) {
            rows = onDutyOnly
                    ? presence.findByDutyStateOrderByLastSeenAtDesc(DutyState.ON_DUTY)
                    : presence.findAllByOrderByLastSeenAtDesc();
        } else {
            rows = onDutyOnly
                    ? presence.findByCarrierIdAndDutyStateOrderByLastSeenAtDesc(scope, DutyState.ON_DUTY)
                    : presence.findByCarrierIdOrderByLastSeenAtDesc(scope);
        }

        return rows.stream()
                .map(row -> RiderPresenceView.of(row, now, presenceWindow))
                // Re-sorted here rather than trusting the SQL order: Postgres sorts NULLs first on
                // a DESC ordering, so a rider who declared duty and never pinged would otherwise
                // head the roster — the least present rider at the top of the presence list.
                .sorted(Comparator.comparing(RiderPresenceView::lastSeenAt,
                        Comparator.nullsLast(Comparator.reverseOrder())))
                .toList();
    }

    /** The fleet a user belongs to, rider or office staff. Empty for platform-employed riders. */
    @Transactional(readOnly = true)
    public Optional<UUID> carrierOf(String userId) {
        return memberships.findById(userId).map(CarrierMembership::getCarrierId);
    }

    // -----------------------------------------------------------------------------------------
    // Cache plumbing
    // -----------------------------------------------------------------------------------------

    private PresenceSnapshot readCache(String riderId) {
        try {
            String raw = redis.opsForValue().get(KEY_PREFIX + riderId);
            return raw == null ? null : objectMapper.readValue(raw, PresenceSnapshot.class);
        } catch (Exception e) {
            // Unreadable or unreachable: fall through to Postgres, which is the record anyway.
            log.warn("Discarding unreadable presence cache entry for a rider", e);
            return null;
        }
    }

    private void cache(PresenceSnapshot snapshot) {
        try {
            redis.opsForValue().set(
                    KEY_PREFIX + snapshot.riderId(),
                    objectMapper.writeValueAsString(snapshot),
                    // The TTL matches the presence window, so an expired key and a stale fix mean
                    // the same thing and cannot disagree.
                    presenceWindow);
        } catch (Exception e) {
            log.warn("Could not cache presence for a rider; reads will go to Postgres", e);
        }
    }

    // -----------------------------------------------------------------------------------------
    // Types
    // -----------------------------------------------------------------------------------------

    /**
     * What is cached, and deliberately what is <em>not</em>: the effective state.
     *
     * <p>Storing "ON_DUTY" in a cache entry would freeze a judgement about freshness into a value
     * that then sits there getting less true. Only the raw facts are cached; the judgement is made
     * on every read against the clock at that moment.
     */
    public record PresenceSnapshot(
            String riderId,
            UUID carrierId,
            DutyState dutyState,
            Instant dutyChangedAt,
            Instant lastSeenAt,
            Double lat,
            Double lng,
            Float accuracyM) {

        static PresenceSnapshot of(RiderPresence row) {
            return new PresenceSnapshot(row.getRiderId(), row.getCarrierId(), row.getDutyState(),
                    row.getDutyChangedAt(), row.getLastSeenAt(), row.getLastLat(), row.getLastLng(),
                    row.getLastAccuracyM());
        }

        PresenceSnapshot withFix(double lat, double lng, Float accuracyM, Instant at) {
            return new PresenceSnapshot(riderId, carrierId, dutyState, dutyChangedAt, at,
                    lat, lng, accuracyM);
        }

        RiderPresenceView toView(Instant now, Duration presenceWindow) {
            PresenceState effective;
            if (dutyState != DutyState.ON_DUTY) {
                effective = PresenceState.OFF_DUTY;
            } else if (lastSeenAt == null || lastSeenAt.isBefore(now.minus(presenceWindow))) {
                effective = PresenceState.STALE;
            } else {
                effective = PresenceState.ON_DUTY;
            }
            return new RiderPresenceView(riderId, carrierId, dutyState, effective, dutyChangedAt,
                    lastSeenAt, lat, lng, accuracyM);
        }
    }

    /**
     * A rider's presence as anyone reading it sees it.
     *
     * @param dutyState what the rider declared
     * @param state     what that means now, having checked when we last heard from them
     */
    public record RiderPresenceView(
            String riderId,
            UUID carrierId,
            DutyState dutyState,
            PresenceState state,
            Instant dutyChangedAt,
            Instant lastSeenAt,
            Double lat,
            Double lng,
            Float accuracyM) {

        static RiderPresenceView of(RiderPresence row, Instant now, Duration presenceWindow) {
            return new RiderPresenceView(row.getRiderId(), row.getCarrierId(), row.getDutyState(),
                    row.effectiveState(now, presenceWindow), row.getDutyChangedAt(),
                    row.getLastSeenAt(), row.getLastLat(), row.getLastLng(), row.getLastAccuracyM());
        }
    }

    /** Thrown when a rider is unknown, or when the caller has no business knowing they exist. */
    public static class PresenceNotFoundException extends RuntimeException {
        public PresenceNotFoundException(String riderId) {
            // The id is not echoed into the message: it goes into an HTTP body, and a value that
            // came from the request path must not be reflected back where something might render
            // it. The correlation id is how a support engineer finds the request.
            super("No presence information for that rider");
        }
    }

    /** Thrown when a caller holds the CARRIER role but belongs to no fleet. */
    public static class NoCarrierException extends RuntimeException {
        public NoCarrierException(String message) {
            super(message);
        }
    }
}
