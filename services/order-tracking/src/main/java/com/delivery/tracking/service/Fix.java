package com.delivery.tracking.service;

import java.time.Instant;

/**
 * One position report from a rider's phone, exactly as it arrived.
 *
 * <p>Nothing here has been believed yet. {@link FixPolicy} decides whether it is, and at what time
 * it is recorded; until then it is a claim from a handset.
 *
 * @param lat       WGS-84 latitude, already bounds-checked by the request body
 * @param lng       WGS-84 longitude, already bounds-checked by the request body
 * @param accuracyM the handset's own radius of uncertainty, in metres. Null when it did not say —
 *                  older app builds, and handsets that do not report one
 * @param takenAt   when the phone took the fix, by the phone's clock. Null from app builds that
 *                  predate the field; those reports are stamped with the moment they arrived, which
 *                  is what every report was stamped with before the field existed
 */
public record Fix(double lat, double lng, Float accuracyM, Instant takenAt) {

    /** A report with no fix time, as every app build before the field sent it. */
    public static Fix untimed(double lat, double lng, Float accuracyM) {
        return new Fix(lat, lng, accuracyM, null);
    }
}
