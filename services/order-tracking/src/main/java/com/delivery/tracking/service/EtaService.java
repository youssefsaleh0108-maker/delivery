package com.delivery.tracking.service;

import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.route.GeoPoint;
import com.delivery.tracking.route.RouteEstimate;
import com.delivery.tracking.route.RouteProvider;
import com.delivery.tracking.route.RouteProviderRegistry;
import com.delivery.tracking.service.TrackingService.Position;
import com.delivery.tracking.service.TrackingService.TrackingNotFoundException;

/**
 * How far the rider still has to go, and roughly when they will arrive.
 *
 * <p>The whole design of this class is about refusing to answer. An ETA is the single most trusted
 * number on a delivery screen — customers plan around it and complain against it — and every input
 * it depends on can legitimately be missing: the rider may not have pinged yet, their phone may
 * have gone quiet, the order may carry no coordinates because the publisher does not send them yet,
 * and the routing provider may be unreachable. In every one of those cases this returns an
 * unavailable result carrying the reason, and never a number.
 *
 * <p>There is no fallback chain. If the configured provider cannot answer a request, the answer is
 * "unavailable", not a straight line computed quietly in its place: a routed ETA and a
 * great-circle-over-an-assumed-speed ETA differ by tens of minutes in a city, and a screen that
 * switched between them mid-delivery would show a jump nobody could explain. The one place a
 * substitution happens is at startup, when a provider is selected but unconfigured, and that is
 * logged loudly by {@code RouteProviderRegistry} and visible in {@link EtaResult#provider()} on
 * every single response.
 */
@Service
public class EtaService {

    /** Nothing is arriving; the delivery is over one way or the other. */
    private static final Set<String> TERMINAL_STATUSES = Set.of("DELIVERED", "CANCELLED");

    private final TrackingService tracking;
    private final OrderParticipantsRepository participants;
    private final RouteProviderRegistry providers;
    private final Duration maxFixAge;

    public EtaService(TrackingService tracking,
                      OrderParticipantsRepository participants,
                      RouteProviderRegistry providers,
                      // Older than this and the rider could be anywhere. Generous compared with the
                      // few seconds between pings, because a customer would rather see a slightly
                      // aged ETA than have it blink out every time a rider goes under a bridge.
                      @Value("${delivery.tracking.eta.max-fix-age:5m}") Duration maxFixAge) {
        this.tracking = tracking;
        this.participants = participants;
        this.providers = providers;
        this.maxFixAge = maxFixAge;
    }

    /**
     * The remaining journey for an order.
     *
     * <p>Authorisation is the same as for the live position — customer, merchant or assigned rider,
     * or backoffice — and is applied here as well as inside {@link TrackingService}, so the reasons
     * below cannot become an oracle: a stranger gets "not found" before learning whether an order
     * has a fix, a destination or a rider at all.
     */
    @Transactional(readOnly = true)
    public EtaResult estimateFor(UUID orderId, String userId, boolean isBackoffice) {
        OrderParticipants order = participants.findById(orderId)
                .orElseThrow(() -> new TrackingNotFoundException(orderId));

        if (!isBackoffice && !order.isVisibleTo(userId)) {
            throw new TrackingNotFoundException(orderId);
        }

        Instant now = Instant.now();
        String provider = providers.active().name();

        if (TERMINAL_STATUSES.contains(order.getStatus())) {
            return EtaResult.unavailable(orderId, Reason.ORDER_COMPLETE, provider, null, now);
        }

        Optional<Position> fix = tracking.currentPosition(orderId, userId, isBackoffice);
        if (fix.isEmpty()) {
            // The rule this endpoint exists to keep. With no fix there is no distance, and a
            // distance guessed from the pickup point would be a number the screen would render as
            // a promise. Absent is honest.
            return EtaResult.unavailable(orderId, Reason.NO_FIX, provider, null, now);
        }

        Position position = fix.get();
        if (position.recordedAt().isBefore(now.minus(maxFixAge))) {
            // Same rule, one step subtler: a fix from twenty minutes ago is not a fix, it is a
            // memory, and an ETA measured from it would be confidently wrong rather than absent.
            return EtaResult.unavailable(orderId, Reason.STALE_FIX, provider,
                    position.recordedAt(), now);
        }

        Optional<GeoPoint> dropoff = order.dropoff();
        if (dropoff.isEmpty()) {
            // No coordinates on the order. Today this is the normal case: the order events this
            // service projects carry a postal address and no lat/lng, so there is nothing to
            // measure against until that contract lands. See V12 and the service report.
            return EtaResult.unavailable(orderId, Reason.NO_DESTINATION, provider,
                    position.recordedAt(), now);
        }

        GeoPoint riderAt = new GeoPoint(position.lat(), position.lng());
        Leg leg = order.isCarrying() ? Leg.TO_DROPOFF : Leg.TO_PICKUP;

        Optional<RouteEstimate> estimate = leg == Leg.TO_DROPOFF
                ? providers.active().estimate(riderAt, dropoff.get())
                : viaPickup(order, riderAt, dropoff.get());

        if (estimate.isEmpty()) {
            // Either the pickup point is missing on a pre-collection order, or the provider could
            // not answer. Both are reported rather than papered over.
            Reason reason = leg == Leg.TO_PICKUP && order.pickup().isEmpty()
                    ? Reason.NO_DESTINATION
                    : Reason.PROVIDER_UNAVAILABLE;
            return EtaResult.unavailable(orderId, reason, provider, position.recordedAt(), now);
        }

        RouteEstimate route = estimate.get();

        // Anchored to when the fix was taken, not to now: the distance was measured from where the
        // rider was at that moment, and the seconds since have been spent covering some of it.
        // Clamped forward to now because an arrival instant in the past is not a prediction — a
        // screen would render it as "arrived" for a rider who is visibly still on the road.
        Instant arrival = position.recordedAt().plus(route.travelTime());
        if (arrival.isBefore(now)) {
            arrival = now;
        }

        return new EtaResult(orderId, true, null, leg,
                route.distanceMetres(), route.travelTime().toSeconds(), arrival,
                route.provider(), position.recordedAt(), now);
    }

    /**
     * Rider → pickup → customer, for an order the rider has not collected yet.
     *
     * <p>Both legs, summed, rather than measuring straight to the customer. A rider four streets
     * the wrong side of the restaurant is not four streets from the customer, and the shortcut
     * would produce an ETA that improves as the rider drives away from the food.
     *
     * <p>Both legs come from the same provider, so a summed estimate can never be half-routed and
     * half-guessed.
     */
    private Optional<RouteEstimate> viaPickup(OrderParticipants order, GeoPoint riderAt,
                                              GeoPoint dropoff) {
        RouteProvider provider = providers.active();
        return order.pickup()
                .flatMap(pickup -> provider.estimate(riderAt, pickup)
                        .flatMap(toPickup -> provider.estimate(pickup, dropoff).map(toPickup::plus)));
    }

    /** Which part of the journey the estimate covers. */
    public enum Leg {
        /** The rider has not collected yet, so the estimate spans rider → pickup → customer. */
        TO_PICKUP,
        /** The rider has the goods; the estimate is the run to the customer. */
        TO_DROPOFF
    }

    /** Why there is no number. Present exactly when {@link EtaResult#available()} is false. */
    public enum Reason {
        /** The rider has never pinged on this order. */
        NO_FIX,
        /** The last ping is older than the acceptable fix age. The rider could be anywhere. */
        STALE_FIX,
        /** The order carries no coordinates to measure against. */
        NO_DESTINATION,
        /** The routing provider could not answer. Transient for a real provider. */
        PROVIDER_UNAVAILABLE,
        /** Delivered or cancelled. Nothing is on its way. */
        ORDER_COMPLETE
    }

    /**
     * @param available        false whenever anything is missing; the numeric fields are then null
     * @param reason           why not, or null when available
     * @param provider         who computed it — or who would have. Always present, so a caller can
     *                         tell a routed answer from a straight-line one without asking
     * @param fixRecordedAt    when the position the estimate was measured from was taken
     */
    public record EtaResult(
            UUID orderId,
            boolean available,
            Reason reason,
            Leg leg,
            Double remainingMetres,
            Long remainingSeconds,
            Instant estimatedArrival,
            String provider,
            Instant fixRecordedAt,
            Instant computedAt) {

        static EtaResult unavailable(UUID orderId, Reason reason, String provider,
                                     Instant fixRecordedAt, Instant now) {
            return new EtaResult(orderId, false, reason, null, null, null, null,
                    provider, fixRecordedAt, now);
        }
    }
}
