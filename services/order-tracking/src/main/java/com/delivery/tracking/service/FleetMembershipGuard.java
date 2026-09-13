package com.delivery.tracking.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.function.Function;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;

import com.delivery.platform.security.CurrentUser;
import com.delivery.tracking.client.CarrierDirectoryClient;
import com.delivery.tracking.domain.CarrierMembershipPeriod;
import com.delivery.tracking.domain.CarrierMembershipPeriodRepository;
import com.delivery.tracking.domain.MembershipWindow;

/**
 * Which riders a delivery company may see, and for when — the check on every carrier read of a
 * rider's presence, position, duty, hours or attendance.
 *
 * <p><strong>Why it exists.</strong> Those reads used to turn on this service's own linkage alone:
 * {@code carrier_membership} and {@code rider_presence.carrier_id}, learned from order events. No
 * order event says a rider left, and carriers can now end a contract themselves, so a company that
 * let a rider go kept watching their position, duty and hours until the rider happened to carry an
 * order for somebody else — and forever if they stopped working. It also saw every shift the rider
 * had ever worked, for anyone, because nothing recorded when the rider was whose.
 *
 * <h2>Is this rider on the caller's fleet now?</h2>
 *
 * <p>Asked of Order Manager, which owns membership:
 * {@code GET /api/delivery-providers/my-company/riders}, with the caller's own token — never a
 * service credential — so it can only ever answer for the caller's own company.
 *
 * <ul>
 *   <li><strong>Cached briefly, per caller</strong> ({@code delivery.tracking.fleet-check.ttl},
 *       30 s). The roster is polled every few seconds; one directory call per poll per dispatcher
 *       would put Order Manager behind the busiest console in the platform. A departure therefore
 *       takes effect within the window.</li>
 *   <li><strong>Fails closed.</strong> When Order Manager cannot be asked and no fresh answer is
 *       held, the read is refused ({@link CarrierDirectoryClient.DirectoryUnavailableException},
 *       a 503) rather than served from a linkage that may be stale. An expired answer is never
 *       served through an outage, and a failure is never cached.</li>
 *   <li><strong>Carrier staff only.</strong> A caller without the CARRIER role, or whose token is
 *       not the caller's, has an empty fleet and costs no call — a customer polls a rider's position
 *       too, and each of those must not become a request Order Manager answers 403 to.</li>
 * </ul>
 *
 * <h2>When was this rider on this company's fleet?</h2>
 *
 * <p>From {@code carrier_membership_periods}, which {@link MembershipPeriodRecorder} keeps from
 * Order Manager's {@code carrier.member_joined} / {@code carrier.member_left} events.
 * <strong>Clip every history read to these windows</strong> ({@link #membershipWindows},
 * {@link #membershipWindowsByRider}): a company may see a rider's duty sessions, hours and
 * attendance only for the time the rider was its rider — never a shift from before it hired them,
 * worked for another company or for YouDrop, nor from after it let them go, nor from a spell away
 * in between. A session crossing a boundary is cut at it. No window means nothing to show, which is
 * also the answer for a rider the record has not heard of yet.
 *
 * <h2>Adopting it</h2>
 *
 * <ol>
 *   <li>Resolve the company as before ({@code CarrierScopeResolver}), never from the request.</li>
 *   <li>A read or a write about one rider: {@link #requireOnCallersFleet} once your own scoping has
 *       passed — the refusal is the same not-found an unknown rider gets. Where the carrier is one of
 *       several kinds of caller, {@link #isOnCallersFleet}.</li>
 *   <li>A listing of riders: {@link #retainCallersFleet}.</li>
 *   <li>Anything drawn from history (sessions, hours, attendance, totals): clip to
 *       {@link #membershipWindows}, or {@link #membershipWindowsByRider} for a whole fleet in one
 *       query. A rider who left during the period keeps the part of it they were the company's.</li>
 *   <li>With no caller's token to ask with — a scheduled job — {@link #isCurrentMember}, the
 *       event-fed record, which can trail Order Manager by the time an event takes to arrive.</li>
 * </ol>
 */
@Component
public class FleetMembershipGuard {

    /** Past this many callers, answers that have expired are swept before another is kept. */
    static final int SWEEP_ABOVE = 512;

    private final CarrierDirectoryClient directory;
    private final CarrierMembershipPeriodRepository periods;
    private final Duration ttl;
    private final Clock clock;
    private final ConcurrentMap<String, KnownFleet> known = new ConcurrentHashMap<>();

    @Autowired
    public FleetMembershipGuard(CarrierDirectoryClient directory,
                                CarrierMembershipPeriodRepository periods,
                                @Value("${delivery.tracking.fleet-check.ttl:30s}") Duration ttl) {
        this(directory, periods, ttl, Clock.systemUTC());
    }

    /** With a clock a test can move past the window. */
    FleetMembershipGuard(CarrierDirectoryClient directory, CarrierMembershipPeriodRepository periods,
                         Duration ttl, Clock clock) {
        this.directory = directory;
        this.periods = periods;
        this.ttl = ttl;
        this.clock = clock;
    }

    // -----------------------------------------------------------------------------------------
    // Now, as Order Manager has it
    // -----------------------------------------------------------------------------------------

    /**
     * The riders on the calling company's fleet now. Empty for a caller who is not carrier staff,
     * or whose company Order Manager does not know.
     *
     * @throws CarrierDirectoryClient.DirectoryUnavailableException when Order Manager cannot be
     *         asked and no answer younger than the window is held
     */
    public Set<String> ridersOnCallersFleet(String callerId) {
        Optional<String> token = tokenOf(callerId);
        if (token.isEmpty()) {
            return Set.of();
        }
        Instant now = clock.instant();
        KnownFleet held = known.get(callerId);
        if (held != null && held.freshAt(now, ttl)) {
            return held.riders();
        }

        // Throws when Order Manager cannot be asked. Nothing is kept then, so the next read asks
        // again instead of repeating a refusal — or serving an old fleet — for the whole window.
        Set<String> riders = directory.ridersFor(token.get());
        if (known.size() > SWEEP_ABOVE) {
            known.values().removeIf(entry -> !entry.freshAt(now, ttl));
        }
        known.put(callerId, new KnownFleet(riders, now));
        return riders;
    }

    /**
     * Whether this rider is on the calling company's fleet now.
     *
     * @throws CarrierDirectoryClient.DirectoryUnavailableException as {@link #ridersOnCallersFleet}
     */
    public boolean isOnCallersFleet(String callerId, String riderId) {
        return riderId != null && ridersOnCallersFleet(callerId).contains(riderId);
    }

    /**
     * Refuses a read about a rider who is not on the calling company's fleet now, with the same
     * not-found an unknown rider gets — so the refusal says nothing about whether the rider exists,
     * or whose fleet they are on instead.
     *
     * @throws PresenceService.PresenceNotFoundException when they are not
     * @throws CarrierDirectoryClient.DirectoryUnavailableException as {@link #ridersOnCallersFleet}
     */
    public void requireOnCallersFleet(String callerId, String riderId) {
        if (!isOnCallersFleet(callerId, riderId)) {
            throw new PresenceService.PresenceNotFoundException(riderId);
        }
    }

    /**
     * The rows whose rider is on the calling company's fleet now, in their order. An empty listing
     * costs no call.
     *
     * @throws CarrierDirectoryClient.DirectoryUnavailableException as {@link #ridersOnCallersFleet}
     */
    public <T> List<T> retainCallersFleet(String callerId, Collection<T> rows,
                                          Function<T, String> riderOf) {
        if (rows.isEmpty()) {
            return List.of();
        }
        Set<String> riders = ridersOnCallersFleet(callerId);
        return rows.stream()
                .filter(row -> riders.contains(riderOf.apply(row)))
                .toList();
    }

    // -----------------------------------------------------------------------------------------
    // When, as the membership record has it
    // -----------------------------------------------------------------------------------------

    /**
     * Whether the membership record has this rider on this company's fleet now — for a caller with
     * no token to ask Order Manager with. On a request, prefer {@link #isOnCallersFleet}: this is
     * fed by events, and trails a change by the time its event takes to arrive.
     */
    public boolean isCurrentMember(UUID carrierId, String riderId) {
        return carrierId != null && riderId != null
                && periods.findByRiderIdAndLeftAtIsNull(riderId)
                        .filter(period -> period.getCarrierId().equals(carrierId))
                        .isPresent();
    }

    /**
     * The stretches of {@code [from, to)} in which this rider was on this company's fleet, oldest
     * first, merged where they touch. <strong>Clip every history read to these windows</strong> —
     * see the class notes. Empty when the rider was never the company's in that range.
     */
    public List<MembershipWindow> membershipWindows(UUID carrierId, String riderId,
                                                    Instant from, Instant to) {
        if (!from.isBefore(to)) {
            return List.of();
        }
        return merged(periods.overlappingForRider(carrierId, riderId, from, to).stream()
                .map(period -> period.within(from, to))
                .flatMap(Optional::stream)
                .toList());
    }

    /**
     * The same for every rider who was on this company's fleet at any point in {@code [from, to)},
     * in one query — for a fleet-wide listing or total. A rider absent from the map was never the
     * company's in that range, however the local linkage reads.
     */
    public Map<String, List<MembershipWindow>> membershipWindowsByRider(UUID carrierId,
                                                                        Instant from, Instant to) {
        if (!from.isBefore(to)) {
            return Map.of();
        }
        Map<String, List<MembershipWindow>> byRider = new LinkedHashMap<>();
        for (CarrierMembershipPeriod period : periods.overlappingForCarrier(carrierId, from, to)) {
            period.within(from, to).ifPresent(window -> byRider
                    .computeIfAbsent(period.getRiderId(), rider -> new ArrayList<>())
                    .add(window));
        }
        byRider.replaceAll((rider, windows) -> merged(windows));
        return byRider;
    }

    /** Sorted by start, with windows that overlap or touch joined into one. */
    static List<MembershipWindow> merged(List<MembershipWindow> windows) {
        List<MembershipWindow> sorted = new ArrayList<>(windows);
        sorted.sort(Comparator.comparing(MembershipWindow::start));
        List<MembershipWindow> joined = new ArrayList<>();
        for (MembershipWindow window : sorted) {
            int last = joined.size() - 1;
            if (last >= 0 && !window.start().isAfter(joined.get(last).end())) {
                MembershipWindow previous = joined.get(last);
                Instant end = window.end().isAfter(previous.end()) ? window.end() : previous.end();
                joined.set(last, new MembershipWindow(previous.start(), end));
            } else {
                joined.add(window);
            }
        }
        return List.copyOf(joined);
    }

    /**
     * The caller's own bearer token, and only ever theirs — the same rule as
     * {@code CarrierScopeResolver}: the directory answers for the holder of the token in hand, so a
     * caller without the CARRIER role, or a subject that is not the token's, is simply not asked
     * about.
     */
    private Optional<String> tokenOf(String callerId) {
        if (!CurrentUser.hasRole("CARRIER")) {
            return Optional.empty();
        }
        return CurrentUser.jwt()
                .filter(jwt -> callerId.equals(jwt.getSubject()))
                .map(Jwt::getTokenValue);
    }

    private record KnownFleet(Set<String> riders, Instant fetchedAt) {
        boolean freshAt(Instant now, Duration ttl) {
            return now.isBefore(fetchedAt.plus(ttl));
        }
    }
}
