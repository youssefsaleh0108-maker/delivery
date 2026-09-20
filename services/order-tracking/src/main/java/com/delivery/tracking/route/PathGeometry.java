package com.delivery.tracking.route;

/**
 * How a path may be drawn on a customer's map.
 *
 * <p>Decided by the server, from the provider that computed the path, so that turning on a routing
 * engine turns every line on every map into a road with no client release: the app draws what this
 * says and nothing else.
 */
public enum PathGeometry {

    /** The provider followed real roads and returned the line; draw it solid, as returned. */
    ROAD,

    /**
     * The provider knows nothing about roads. Draw dashed straight segments between the stops and
     * say that they are approximate — never a curve, which would look like a road.
     */
    STRAIGHT
}
