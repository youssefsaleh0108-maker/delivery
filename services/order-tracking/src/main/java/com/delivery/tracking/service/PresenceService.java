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
import com.delivery.tracking.domain.DutySession;
import com.delivery.tracking.domain.DutySessionRepository;
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

    /** Where {@link LatestFix} lives: the rider's last accepted fix and the order it went on. */
    private static final String LATEST_FIX_PREFIX = "delivery:tracking:rider-latest-fix:";

    /**
     * How long the rider's last accepted fix, and the order it went on, is remembered.
     *
     * <p>Far longer than the presence window on purpose. A rider who switches to a navigation app
     * stops reporting (the app shares only in the foreground), and a customer whose order is in
     * their hands must still be shown the last position that was attached to it, with its time,
     * rather than nothing. Overwritten by every accepted fix, so the length only matters for a
     * rider who has gone quiet; and when the key is gone the order-scoped reads show nothing to
     * anybody but the rider and the back office — they fail closed, never open.
     */
    static final Duration LATEST_FIX_TTL = Duration.ofHours(12);

    private final RiderPresenceRepository presence;
    private final RiderDutyEventRepository dutyEvents;
    private final DutySessionRepository dutySessions;
    private final CarrierMembershipRepository memberships;
    /** Resolves the caller's own fleet, asking Order Manager when this service does not know. */
    private final CarrierScopeResolver carrierScope;
    private final OrderParticipantsRepository participants;
    private final StringRedisTemplate redis;
    private final ObjectMapper objectMapper;
    private final Duration presenceWindow;
    private final Duration persistInterval;
    /** Confirms with Order Manager that a rider the local linkage nominates is on the fleet NOW. */
    private final FleetMembershipGuard fleetGuard;
    /** Whether a reported position is believable enough to record — see {@link #recordFix}. */
    private final FixPolicy fixPolicy;

    public PresenceService(RiderPresenceRepository presence,
                           RiderDutyEventRepository dutyEvents,
                           DutySessionRepository dutySessions,
                           CarrierMembershipRepository memberships,
                           CarrierScopeResolver carrierScope,
                           OrderParticipantsRepository participants,
                           StringRedisTemplate redis,
                           ObjectMapper objectMapper,
                           @Value("${delivery.tracking.presence.ttl:120s}") Duration presenceWindow,
                           @Value("${delivery.tracking.presence.persist-interval:30s}") Duration persistInterval,
                           FleetMembershipGuard fleetGuard,
                           FixPolicy fixPolicy) {
        this.presence = presence;
        this.dutyEvents = dutyEvents;
        this.dutySessions = dutySessions;
        this.memberships = memberships;
        this.carrierScope = carrierScope;
        this.participants = participants;
        this.redis = redis;
        this.objectMapper = objectMapper;
        this.presenceWindow = presenceWindow;
        this.persistInterval = persistInterval;
        this.fleetGuard = fleetGuard;
        this.fixPolicy = fixPolicy;
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

        // The session is reconciled against what is actually open, not against the transition flag.
        // Open-if-none rather than open-on-transition makes a repeated ON_DUTY declaration a no-op
        // (idempotent, however many times the app re-asserts it) and lets a rider whose previous
        // session was expired-or-missing start accruing hours on their next declaration instead of
        // needing a full off/on cycle. The partial unique index on open sessions backs the check,
        // so two concurrent declarations cannot leave two shifts both accruing hours.
        if (state == DutyState.ON_DUTY) {
            if (dutySessions.findByRiderIdAndEndedAtIsNull(riderId).isEmpty()) {
                dutySessions.save(DutySession.open(riderId, now));
            }
        } else {
            // Close-if-open: a rider who was on duty before duty_sessions existed has no open
            // session, and going off duty simply closes nothing — history starts at the migration
            // and is never invented backwards.
            dutySessions.findByRiderIdAndEndedAtIsNull(riderId).ifPresent(session -> {
                session.close(now, endReasonOf(source));
                dutySessions.save(session);
            });
        }

        cache(PresenceSnapshot.of(row));
        return RiderPresenceView.of(row, now, presenceWindow);
    }

    /**
     * Who ended the shift, derived from who made the declaration. SYSTEM maps to EXPIRED because
     * the only declaration the platform itself makes is the staleness sweep giving up on a rider —
     * see {@link DutySessionService#expireAbandoned}.
     */
    private static DutySession.EndReason endReasonOf(RiderDutyEvent.Source source) {
        return switch (source) {
            case RIDER -> DutySession.EndReason.RIDER;
            case BACKOFFICE -> DutySession.EndReason.BACKOFFICE;
            case SYSTEM -> DutySession.EndReason.EXPIRED;
        };
    }

    /**
     * Records a fix for a rider, whether or not they are carrying anything.
     *
     * <p>Called from {@link TrackingService#ping} — an order ping is evidence of life too, and a
     * rider mid-delivery who did not count as present would drop off the roster the moment they
     * picked something up — and, behind the duty check, from {@link #recordOffOrderFix}. Whoever
     * calls it has already decided the rider may report at all.
     *
     * <p>Never changes duty state. A location is evidence that a phone is alive, not consent to be
     * given work.
     *
     * <p>The fix is judged by {@link FixPolicy} against the last one accepted for this rider before
     * anything is written, so a refused fix leaves no trace in either store — and in particular
     * does not become the anchor the next fix is compared with. A fix that adds nothing new (not
     * newer than the last one, or too soon after it) is not written either, and is not refused.
     *
     * <p>Also remembers which order the fix went on ({@link #latestFix}). That is what decides, for
     * everyone but the back office, whose map may show the rider: the customer of the delivery the
     * rider's latest fix was attached to, and nobody else's (see
     * {@link TrackingService#sightingFor}).
     *
     * @param orderId the order the fix was reported on, or null for a fix reported on none
     * @return the instant the fix is recorded at — the phone's fix time, never later than now — or
     *         empty when it was not new enough to record
     * @throws FixPolicy.FixRejectedException when the fix is not believable
     */
    @Transactional
    public Optional<Instant> recordFix(String riderId, Fix fix, UUID orderId) {
        return record(riderId, fix, readCache(riderId), orderId);
    }

    /**
     * The off-order ping: a rider reporting where they are while no order names them.
     *
     * <p>Only a rider who is working may do this — declared on duty, or holding a live order. The
     * rule used to be "anyone with the rider role", which let a rider who had gone home keep
     * feeding a position into the fleet's roster, and let an app that never checked duty report a
     * location nobody had asked for. Declared duty rather than effective: a rider who is on duty
     * and has gone STALE is exactly the one whose next fix must be let in.
     *
     * <p>The order-scoped ping does not come through here; it has its own and narrower rule, that
     * the caller is the rider assigned to that order ({@link TrackingService#ping}).
     *
     * @return as {@link #recordFix}: when the fix is recorded at, or empty when it was not new
     * @throws OffDutyException when the rider is neither on duty nor carrying anything
     */
    @Transactional
    public Optional<Instant> recordOffOrderFix(String riderId, Fix fix) {
        PresenceSnapshot cached = readCache(riderId);
        boolean onDuty = cached != null
                ? cached.dutyState() == DutyState.ON_DUTY
                : presence.findById(riderId)
                        .map(row -> row.getDutyState() == DutyState.ON_DUTY)
                        .orElse(false);
        if (!onDuty && !participants.riderHasLiveOrder(riderId)) {
            throw new OffDutyException();
        }
        // Attached to no order, so from here on no customer's or shop's map shows the rider until
        // a fix goes on one of theirs again.
        return record(riderId, fix, cached, null);
    }

    private Optional<Instant> record(String riderId, Fix fix, PresenceSnapshot cached,
                                     UUID orderId) {
        Instant now = Instant.now();

        if (cached == null) {
            // Cold: either this rider is new, or Redis has forgotten them (eviction, restart, or
            // Redis being down entirely). Settle it against the record and write through.
            RiderPresence row = presence.findById(riderId)
                    .orElseGet(() -> RiderPresence.firstSeen(riderId, now));
            FixPolicy.Admission admission = fixPolicy.admit(fix, FixPolicy.Previous.of(
                    row.getLastLat(), row.getLastLng(), row.getLastAccuracyM(),
                    row.getLastSeenAt()), now);
            if (!admission.recorded()) {
                return Optional.empty();
            }
            row.sighted(fix.lat(), fix.lng(), fix.accuracyM(), admission.at());
            presence.save(row);
            cache(PresenceSnapshot.of(row));
            rememberLatest(new LatestFix(riderId, orderId, fix.lat(), fix.lng(), fix.accuracyM(),
                    admission.at()));
            return Optional.of(admission.at());
        }

        // Warm: judged against the cached snapshot, which carries the exact last fix — the durable
        // row lags it by up to the persist interval, so comparing with the row would measure a
        // jump from somewhere the rider was half a minute ago.
        FixPolicy.Admission admission = fixPolicy.admit(fix, FixPolicy.Previous.of(cached.lat(),
                cached.lng(), cached.accuracyM(), cached.lastSeenAt()), now);
        if (!admission.recorded()) {
            return Optional.empty();
        }
        Instant at = admission.at();
        // A cached snapshot exists, so the durable row does too. Move it only if the throttle is
        // due — see RiderPresenceRepository#touchIfDue for what this trades away and why.
        presence.touchIfDue(riderId, fix.lat(), fix.lng(), fix.accuracyM(), at,
                at.minus(persistInterval));
        cache(cached.withFix(fix.lat(), fix.lng(), fix.accuracyM(), at));
        rememberLatest(new LatestFix(riderId, orderId, fix.lat(), fix.lng(), fix.accuracyM(), at));
        return Optional.of(at);
    }

    /**
     * The rider's last accepted fix, and the order it was reported on.
     *
     * <p>Held in Redis only, under {@link #LATEST_FIX_TTL}: there is no column for the order
     * without a migration. Empty when the rider has not reported since, or when Redis has lost it
     * or cannot be reached — and everything that reads it treats empty as "show nobody", so losing
     * it costs customers the rider's dot until the next fix, and never shows it to the wrong one.
     */
    public Optional<LatestFix> latestFix(String riderId) {
        if (riderId == null) {
            return Optional.empty();
        }
        try {
            String raw = redis.opsForValue().get(LATEST_FIX_PREFIX + riderId);
            return raw == null
                    ? Optional.empty()
                    : Optional.of(objectMapper.readValue(raw, LatestFix.class));
        } catch (Exception e) {
            log.warn("Could not read a rider's latest fix; their position is shown to nobody "
                    + "outside the back office until the next one", e);
            return Optional.empty();
        }
    }

    private void rememberLatest(LatestFix latest) {
        try {
            redis.opsForValue().set(LATEST_FIX_PREFIX + latest.riderId(),
                    objectMapper.writeValueAsString(latest), LATEST_FIX_TTL);
        } catch (Exception e) {
            // Never fails the fix. The reads that need this fail closed without it.
            log.warn("Could not remember a rider's latest fix", e);
        }
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
     * <p>Three callers may ask, and the list is deliberately short, because a rider's position is
     * personal data about a worker rather than a property of an order:
     *
     * <ul>
     *   <li>the rider themselves;</li>
     *   <li>backoffice, which is what the support role is for — the last known position, with the
     *       time it was taken ({@code lastSeenAt}), on duty or not;</li>
     *   <li>the fleet that employs them — their own dispatcher, and nobody else's — and the
     *       position only while the rider is declared on duty. Off duty, the fleet still sees the
     *       duty state and when the phone last reported, but not where: a last fix outlives the
     *       shift, and is often near home.</li>
     * </ul>
     *
     * <p>Customers and shops are <em>not</em> on that list. They see a rider through their order
     * ({@code GET /api/tracking/orders/{id}}), where one rule decides what each may see and when
     * (TrackingService#sightingFor): a person-scoped read beside it would be a second door with a
     * different rule — it used to show a customer the rider for as long as any order of theirs was
     * in the rider's hands, wherever the rider was going.
     *
     * <p>A caller who is none of these gets the same {@code not found} as a caller asking about a
     * rider id that does not exist. 403 would confirm the rider is real, which is enough to let
     * somebody enumerate the fleet.
     */
    @Transactional(readOnly = true)
    public RiderPresenceView locationOf(String riderId, String callerId, boolean isBackoffice) {
        boolean unrestricted = callerId.equals(riderId) || isBackoffice;
        if (!unrestricted && !employsRider(callerId, riderId)) {
            throw new PresenceNotFoundException(riderId);
        }
        RiderPresenceView view = ownPresence(riderId)
                .orElseThrow(() -> new PresenceNotFoundException(riderId));
        return unrestricted ? view : view.asSeenByFleet();
    }

    private boolean employsRider(String callerId, String riderId) {
        // Resolved rather than merely looked up: a dispatcher asking where their own rider is has
        // no row here until somebody asks Order Manager for one. The RIDER's fleet is only ever
        // read — we hold no token for them, and an order event is how a rider's row appears.
        Optional<UUID> callerCarrier = carrierScope.scopeFor(callerId);
        // The local linkage only nominates: it is learned from order events, and nothing but a
        // membership event clears it. Order Manager, asked with the caller's own token, confirms
        // the rider is on that fleet NOW, so a company that let the rider go stops seeing where
        // they are, and an Order Manager that cannot be reached refuses rather than trusting the
        // linkage. Asked last, so a customer or a stranger never costs a cross-service call.
        return callerCarrier.isPresent() && callerCarrier.equals(carrierOf(riderId))
                && fleetGuard.isOnCallersFleet(callerId, riderId);
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
     *
     * <p>Positions as {@link #locationOf} gives them: the back office sees every rider's last known
     * position with its time; a carrier sees a rider's position only while the rider is declared on
     * duty — {@code onDutyOnly=false} lists the off-duty riders too, without where they are.
     */
    @Transactional(readOnly = true)
    public List<RiderPresenceView> roster(String callerId, boolean isBackoffice,
                                          UUID requestedCarrierId, boolean onDutyOnly) {
        Instant now = Instant.now();

        UUID scope;
        if (isBackoffice) {
            scope = requestedCarrierId;
        } else {
            scope = carrierScope.requireScopeFor(callerId);
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

        if (!isBackoffice) {
            // Only riders on the caller's fleet NOW, as Order Manager has it. A membership event
            // clears the carrier_id the query above filters on, but an event can be late or lost,
            // and without this a company that let a rider go could keep their live position and
            // duty on its roster. See FleetMembershipGuard.
            rows = fleetGuard.retainCallersFleet(callerId, rows, RiderPresence::getRiderId);
        }

        return rows.stream()
                .map(row -> RiderPresenceView.of(row, now, presenceWindow))
                .map(view -> isBackoffice ? view : view.asSeenByFleet())
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
     * <p>A position never travels without its time: {@code lat}, {@code lng} and
     * {@code accuracyM} are present only together with {@code lastSeenAt}, which is when that
     * fix was taken. A last known position read without its age reads as "here now".
     *
     * @param dutyState  what the rider declared
     * @param state      what that means now, having checked when we last heard from them
     * @param lastSeenAt when the last fix was taken — the time of {@code lat}/{@code lng}
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

        public RiderPresenceView {
            if (lastSeenAt == null) {
                lat = null;
                lng = null;
                accuracyM = null;
            }
        }

        static RiderPresenceView of(RiderPresence row, Instant now, Duration presenceWindow) {
            return new RiderPresenceView(row.getRiderId(), row.getCarrierId(), row.getDutyState(),
                    row.effectiveState(now, presenceWindow), row.getDutyChangedAt(),
                    row.getLastSeenAt(), row.getLastLat(), row.getLastLng(), row.getLastAccuracyM());
        }

        /**
         * As the rider's fleet sees it: everything, but the position only while the rider is
         * declared on duty. A rider's last fix outlives their shift — it is often near home — and
         * nobody but the back office keeps sight of it once they have gone off duty.
         */
        public RiderPresenceView asSeenByFleet() {
            if (dutyState == DutyState.ON_DUTY) {
                return this;
            }
            return new RiderPresenceView(riderId, carrierId, dutyState, state, dutyChangedAt,
                    lastSeenAt, null, null, null);
        }
    }

    /**
     * A rider's last accepted fix and the order it was reported on.
     *
     * @param orderId the order the fix went on, or null when it was reported on none (between
     *                jobs, or with no single delivery the app could attach it to)
     * @param at      when it was taken, as recorded
     */
    public record LatestFix(String riderId, UUID orderId, double lat, double lng,
                            Float accuracyM, Instant at) {
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

    /**
     * Thrown when a rider reports a position while neither on duty nor carrying an order.
     *
     * <p>A 409 at the edge rather than a 404 or a 403: the rider is who they say they are and may
     * use the endpoint — just not in their current state, and going on duty changes the answer.
     */
    public static class OffDutyException extends RuntimeException {
        public OffDutyException() {
            super("You are off duty with no delivery in hand, so your location is not recorded. "
                    + "Go on duty to share it.");
        }
    }

    /** Thrown when a caller holds the CARRIER role but belongs to no fleet. */
    public static class NoCarrierException extends RuntimeException {
        public NoCarrierException(String message) {
            super(message);
        }
    }
}
