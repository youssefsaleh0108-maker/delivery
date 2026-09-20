package com.delivery.tracking.route;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * The lines a checkout map draws, through whichever provider is live, and kept where that
 * provider's terms allow.
 *
 * <p>Two kinds of path, cached differently because they change differently:
 * <ul>
 *   <li><b>Planned</b> — shop → door, before anyone is on the way. The same two pins give the same
 *       road all day, so a routed answer is kept for a day, keyed by provider and by the stops
 *       rounded to five decimal places (about a metre: a pin nudged by a rounding error is the same
 *       pin).</li>
 *   <li><b>Rider legs</b> — from the rider's latest fix through the stops still ahead, keyed by
 *       that rider and the reader being drawn them as well as by the stops. The rider moves, so
 *       the leg is recomputed only once they have moved {@code leg-refresh-metres} from where it
 *       was last routed from, or {@code leg-refresh-after} has passed. Between those, every
 *       refresh of that reader's screens reuses one routed answer.</li>
 * </ul>
 *
 * <p>Only a provider that says it {@link RouteProvider#mayCachePaths() may be cached} is: OSRM,
 * which is the platform's own server. Mapbox's terms forbid storing its results, and the dev
 * provider is arithmetic that costs less than a Redis round trip, so both are asked every time.
 *
 * <p>Never mixed: the provider's name is part of every key and is checked again on the way out, so
 * a path routed by one provider is never served while another is live. And Redis is an
 * optimisation here, never a dependency — when it cannot be reached, the provider is asked directly.
 */
@Component
public class RoutePaths {

    private static final Logger log = LoggerFactory.getLogger(RoutePaths.class);

    static final String PLANNED_PREFIX = "delivery:tracking:route:planned:";
    static final String LEG_PREFIX = "delivery:tracking:route:leg:";

    private final RouteProviderRegistry providers;
    private final StringRedisTemplate redis;
    private final ObjectMapper objectMapper;
    private final Duration plannedTtl;
    private final double legRefreshMetres;
    private final Duration legRefreshAfter;

    public RoutePaths(RouteProviderRegistry providers,
                      StringRedisTemplate redis,
                      ObjectMapper objectMapper,
                      // A road between two fixed pins does not change during a day's deliveries.
                      @Value("${delivery.tracking.routing.paths.planned-ttl:24h}") Duration plannedTtl,
                      // Far enough that GPS jitter at a traffic light does not re-route; near enough
                      // that the drawn leg still starts at the rider's marker.
                      @Value("${delivery.tracking.routing.paths.leg-refresh-metres:150}")
                      double legRefreshMetres,
                      @Value("${delivery.tracking.routing.paths.leg-refresh-after:60s}")
                      Duration legRefreshAfter) {
        this.providers = providers;
        this.redis = redis;
        this.objectMapper = objectMapper;
        this.plannedTtl = plannedTtl;
        this.legRefreshMetres = legRefreshMetres;
        this.legRefreshAfter = legRefreshAfter;
    }

    /** Who draws the paths right now — named on every response that carries one. */
    public String providerName() {
        return providers.active().name();
    }

    /** How the live provider's paths are drawn: roads, or straight lines said to be approximate. */
    public PathGeometry geometry() {
        return providers.active().pathGeometry();
    }

    /**
     * A path nobody is on yet, through {@code stops} in order — in practice shop → door.
     *
     * <p>Empty when the provider cannot answer; an empty answer is never cached, so a routing host
     * that was briefly down is asked again on the next refresh rather than a day later.
     */
    public Optional<RoutePath> planned(List<GeoPoint> stops) {
        RouteProvider provider = providers.active();
        if (!provider.mayCachePaths()) {
            return orStraight(provider.path(stops), stops);
        }
        String key = PLANNED_PREFIX + provider.name() + ":" + keyOf(stops);
        Optional<Stored> cached = read(key);
        if (cached.isPresent() && cached.get().provider().equals(provider.name())) {
            return Optional.of(cached.get().toPath());
        }
        Optional<RoutePath> fresh = provider.path(stops);
        fresh.ifPresent(path -> write(key, Stored.of(path, null), plannedTtl));
        return orStraight(fresh, stops);
    }

    /**
     * A rider's remaining journey: from {@code from} through {@code ahead} in order, the last of
     * which is the door.
     *
     * <p>Valid while the rider is within {@code leg-refresh-metres} of where the stored leg was
     * routed from. A leg routed from a point that close is the same road for the customer's
     * purposes, and its length and time are what the stored answer says until the refresh window
     * closes.
     *
     * <p>Keyed by the rider and the reader as well as the stops, because the stored leg's geometry
     * <em>starts at where it was routed from</em> — a point up to the refresh distance away from
     * the rider it is now drawn for. Keyed by the stops alone, two riders heading to the same
     * remaining stops would be drawn from each other's positions, and a leg routed for a reader
     * who may see more of the rider (the back office) would be drawn for one who may see less. A
     * reader only ever gets a line that starts where that reader's own rider was.
     *
     * @param riderId whose journey this is
     * @param reader  who is being drawn it, as the checkout map keys its own answers
     */
    public Optional<RoutePath> riderLeg(String riderId, String reader, GeoPoint from,
                                        List<GeoPoint> ahead) {
        RouteProvider provider = providers.active();
        List<GeoPoint> stops = new ArrayList<>(ahead.size() + 1);
        stops.add(from);
        stops.addAll(ahead);
        if (!provider.mayCachePaths()) {
            return orStraight(provider.path(stops), stops);
        }
        String key = LEG_PREFIX + provider.name() + ":" + riderId + ":" + reader + ":"
                + keyOf(ahead);
        Optional<Stored> cached = read(key);
        if (cached.isPresent()
                && cached.get().provider().equals(provider.name())
                && cached.get().originLat() != null
                && cached.get().originLng() != null
                && HaversineRouteProvider.distanceMetres(from,
                        new GeoPoint(cached.get().originLat(), cached.get().originLng()))
                        < legRefreshMetres) {
            return Optional.of(cached.get().toPath());
        }
        Optional<RoutePath> fresh = provider.path(stops);
        // The time half of the refresh rule is the entry's own expiry.
        fresh.ifPresent(path -> write(key, Stored.of(path, from), legRefreshAfter));
        return orStraight(fresh, stops);
    }

    /**
     * The routed path, or straight segments between the same stops when the provider could not
     * answer — a timeout, an outage, a stretch it has no route for.
     *
     * <p>Drawing something is right here and wrong for an ETA, and the difference is what each one
     * claims. A straight path says out loud that it is straight: it carries no road geometry, so
     * the client dashes it and labels the map approximate, and it names the provider that produced
     * it. A number cannot say that; it would just be a different number, so {@code EtaService}
     * still reports the outage instead (PROVIDER_UNAVAILABLE) and shows no time at all.
     *
     * <p>Never cached: a fallback is a fact about this moment, not about these two pins.
     */
    private Optional<RoutePath> orStraight(Optional<RoutePath> routed, List<GeoPoint> stops) {
        if (routed.isPresent()) {
            return routed;
        }
        RouteProvider straight = providers.straightLines();
        if (straight == null || straight == providers.active()) {
            return routed;
        }
        log.warn("The routing provider drew no path through {} stops; falling back to straight "
                + "lines, which the map says are approximate", stops.size());
        return straight.path(stops);
    }

    /** The stops rounded to five decimal places, in order: about a metre, which is one pin. */
    static String keyOf(List<GeoPoint> stops) {
        StringBuilder key = new StringBuilder();
        for (GeoPoint stop : stops) {
            if (!key.isEmpty()) {
                key.append(';');
            }
            key.append(String.format(Locale.ROOT, "%.5f,%.5f", stop.lat(), stop.lng()));
        }
        return key.toString();
    }

    private Optional<Stored> read(String key) {
        try {
            String json = redis.opsForValue().get(key);
            return json == null ? Optional.empty() : Optional.of(objectMapper.readValue(json, Stored.class));
        } catch (Exception e) {
            // Unreachable or unreadable: route afresh. A corrupt entry is dropped by the write that
            // follows, which overwrites it.
            log.warn("Could not read a cached route path; routing afresh", e);
            return Optional.empty();
        }
    }

    private void write(String key, Stored value, Duration ttl) {
        try {
            redis.opsForValue().set(key, objectMapper.writeValueAsString(value), ttl);
        } catch (Exception e) {
            // Losing the cache costs a routing request next time, never the map.
            log.warn("Could not cache a route path", e);
        }
    }

    /**
     * What is kept in Redis: the path in plain numbers, and — for a rider leg — where it was routed
     * from. Plain fields rather than {@link RoutePath} itself, so the stored form does not depend
     * on how a mapper happens to write a {@link Duration}.
     */
    record Stored(double metres, long seconds, String provider, String polyline6,
                  Double originLat, Double originLng) {

        static Stored of(RoutePath path, GeoPoint origin) {
            return new Stored(path.distanceMetres(), path.travelTime().toSeconds(), path.provider(),
                    path.polyline6(), origin == null ? null : origin.lat(),
                    origin == null ? null : origin.lng());
        }

        RoutePath toPath() {
            return new RoutePath(metres, Duration.ofSeconds(seconds), provider, polyline6);
        }
    }
}
