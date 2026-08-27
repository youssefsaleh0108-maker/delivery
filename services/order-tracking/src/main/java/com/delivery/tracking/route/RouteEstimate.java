package com.delivery.tracking.route;

import java.time.Duration;

/**
 * How far and how long, and — always — who says so.
 *
 * <p>{@code provider} is not decoration. A number produced by a straight line at an assumed average
 * speed and a number produced by a real routing engine over real roads are not the same kind of
 * fact, and any screen or log that shows one must be able to tell which it has. Carrying the
 * provider name in the value itself means it cannot be dropped on the way to the caller.
 *
 * @param distanceMetres  metres remaining along whatever path the provider used
 * @param travelTime      how long the provider thinks that takes
 * @param provider        the {@link RouteProvider#name()} that computed it
 */
public record RouteEstimate(double distanceMetres, Duration travelTime, String provider) {

    public RouteEstimate {
        if (distanceMetres < 0) {
            throw new IllegalArgumentException("Distance cannot be negative: " + distanceMetres);
        }
        if (travelTime.isNegative()) {
            throw new IllegalArgumentException("Travel time cannot be negative: " + travelTime);
        }
    }

    /**
     * Adds a following leg to this one.
     *
     * <p>Used when a rider has not collected yet and the remaining journey is rider → pickup →
     * customer. The provider name is taken from this leg because both legs come from the same
     * provider by construction — {@code EtaService} never mixes them, precisely so a summed
     * estimate cannot be half-routed and half-guessed.
     */
    public RouteEstimate plus(RouteEstimate next) {
        return new RouteEstimate(
                distanceMetres + next.distanceMetres,
                travelTime.plus(next.travelTime),
                provider);
    }
}
