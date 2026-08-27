package com.delivery.product.domain;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * A point on the earth, validated.
 *
 * <p>A value object rather than a pair of loose {@code BigDecimal}s because a coordinate has
 * invariants that every entry point needs and that are easy to enforce in exactly one place and
 * nowhere else. {@link Store} takes one of these, the geocoder returns them, and the nearby query
 * takes one — so a coordinate that reaches any of them has already been checked.
 *
 * <p>{@code BigDecimal}, not {@code double}, to match the {@code numeric(9, 6)} columns. Coordinates
 * are not money, so the usual reason does not apply, but the round trip does: a double read back
 * from {@code numeric} and compared to what the merchant typed will differ in the last place, and a
 * "you moved my pin" support ticket is not worth the two bytes.
 */
public record GeoPoint(BigDecimal latitude, BigDecimal longitude) {

    /**
     * Six decimal places — roughly 11 cm at the equator, and exactly what {@code numeric(9, 6)}
     * stores. Normalising here rather than letting Postgres round means the value this service
     * returns is the value it wrote.
     */
    public static final int SCALE = 6;

    private static final BigDecimal MIN_LATITUDE = new BigDecimal("-90");
    private static final BigDecimal MAX_LATITUDE = new BigDecimal("90");
    private static final BigDecimal MIN_LONGITUDE = new BigDecimal("-180");
    private static final BigDecimal MAX_LONGITUDE = new BigDecimal("180");

    /** Mean earth radius, metres. The sphere the haversine below is computed on. */
    private static final double EARTH_RADIUS_METRES = 6_371_008.8;

    public GeoPoint {
        if (latitude == null || longitude == null) {
            // Half a pin is not a pin. Accepting a latitude with no longitude would put a store on
            // the map at a longitude somebody else's code invented.
            throw new InvalidCoordinateException("A location needs both a latitude and a longitude");
        }
        if (latitude.compareTo(MIN_LATITUDE) < 0 || latitude.compareTo(MAX_LATITUDE) > 0) {
            throw new InvalidCoordinateException("Latitude must be between -90 and 90");
        }
        if (longitude.compareTo(MIN_LONGITUDE) < 0 || longitude.compareTo(MAX_LONGITUDE) > 0) {
            throw new InvalidCoordinateException("Longitude must be between -180 and 180");
        }

        latitude = latitude.setScale(SCALE, RoundingMode.HALF_UP);
        longitude = longitude.setScale(SCALE, RoundingMode.HALF_UP);

        // Null Island. Zero is what an uninitialised float, a dropped form field and a failed parse
        // all produce, so (0, 0) is overwhelmingly a bug rather than a shop 600 km off the coast of
        // Ghana. Refusing it costs one imaginary buoy and catches the whole class of "the pin
        // silently never got set" faults, which are otherwise invisible until a customer is shown a
        // map of the Gulf of Guinea.
        if (latitude.signum() == 0 && longitude.signum() == 0) {
            throw new InvalidCoordinateException(
                    "(0, 0) is not a location this platform accepts — it is almost always an "
                            + "unset field rather than a point in the Gulf of Guinea");
        }
    }

    /** Convenience for callers holding primitives, e.g. a geocoder response or a query parameter. */
    public static GeoPoint of(double latitude, double longitude) {
        return new GeoPoint(BigDecimal.valueOf(latitude), BigDecimal.valueOf(longitude));
    }

    /**
     * Builds a point from two nullable values, or nothing when neither is set.
     *
     * <p>Exists so "this store has no pin" stays a null rather than becoming an exception at every
     * read site. One value set and the other not is still an error — see the compact constructor.
     */
    public static GeoPoint ofNullable(BigDecimal latitude, BigDecimal longitude) {
        if (latitude == null && longitude == null) {
            return null;
        }
        return new GeoPoint(latitude, longitude);
    }

    /**
     * Great-circle distance in metres.
     *
     * <p>Haversine on a sphere, not Vincenty on the spheroid. The difference is about 0.3% — some
     * twenty metres over a five-kilometre delivery radius — which is far inside the error already
     * present in a hand-dropped pin, and it costs no dependency and no database round trip.
     *
     * <p>This, and not PostGIS, is the number a customer is shown. See
     * {@link StoreRepository#findActiveIdsNear} for why the database narrows the candidates but does
     * not compute the answer.
     */
    public double distanceMetresTo(GeoPoint other) {
        double lat1 = Math.toRadians(latitude.doubleValue());
        double lat2 = Math.toRadians(other.latitude.doubleValue());
        double deltaLat = lat2 - lat1;
        double deltaLon = Math.toRadians(other.longitude.doubleValue() - longitude.doubleValue());

        double a = Math.pow(Math.sin(deltaLat / 2), 2)
                + Math.cos(lat1) * Math.cos(lat2) * Math.pow(Math.sin(deltaLon / 2), 2);

        // atan2 rather than asin: asin loses precision for antipodal points, where the argument
        // approaches 1 and its derivative blows up.
        return 2 * EARTH_RADIUS_METRES * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    /** Rejected coordinates. Mapped to 400 by {@code ApiExceptionHandler}. */
    public static class InvalidCoordinateException extends IllegalArgumentException {
        public InvalidCoordinateException(String message) {
            super(message);
        }
    }
}
