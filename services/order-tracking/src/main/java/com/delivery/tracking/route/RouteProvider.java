package com.delivery.tracking.route;

import java.util.Optional;

/**
 * Something that can say how far apart two points are and how long it takes to get between them.
 *
 * <p>The same shape the SMS connector uses for its vendors, and for the same reason: the platform
 * has to work before a commercial routing account exists, and switching to one afterwards must be
 * configuration rather than a development project. {@link HaversineRouteProvider} is the dev
 * implementation and is honest about being one; {@link OsrmRouteProvider} and
 * {@link MapboxRouteProvider} are the real ones and refuse to answer until they are configured.
 *
 * <p>Returning {@link Optional} rather than throwing is deliberate. "I cannot answer this" is a
 * normal outcome for a routing provider — no route exists across water, the vendor is down, no key
 * is provisioned — and an ETA screen showing nothing is a correct outcome for it. It is the caller,
 * {@code EtaService}, that turns an empty answer into an explicit "unavailable" rather than into a
 * number from somewhere else.
 */
public interface RouteProvider {

    /**
     * The name that ends up in {@link RouteEstimate#provider()} and in the API response, so a
     * client can tell a routed answer from a straight-line one.
     */
    String name();

    /**
     * Whether this provider currently has what it needs to answer at all.
     *
     * <p>Separate from {@link #estimate} so a misconfiguration surfaces at selection time — with a
     * log line naming the missing setting — instead of as a silently empty ETA on every request.
     */
    boolean isConfigured();

    /** Empty when this provider cannot answer; never a guess in place of a real route. */
    Optional<RouteEstimate> estimate(GeoPoint from, GeoPoint to);
}
