package com.delivery.tracking.domain;

import java.time.Instant;
import java.util.Objects;
import java.util.Optional;

/**
 * A stretch of time a rider belonged to one delivery company, clipped to the range that was asked
 * about: {@code start} inclusive, {@code end} exclusive, and never empty.
 *
 * <p>What a carrier's view of a rider's history is cut to. A shift, or the part of one, outside
 * every window was worked for somebody else — or before the company hired the rider, or after it
 * let them go — and is not the company's to see.
 */
public record MembershipWindow(Instant start, Instant end) {

    public MembershipWindow {
        Objects.requireNonNull(start, "start");
        Objects.requireNonNull(end, "end");
        if (!start.isBefore(end)) {
            throw new IllegalArgumentException("A membership window must end after it starts");
        }
    }

    /** Whether this instant falls inside the window. */
    public boolean contains(Instant at) {
        return !at.isBefore(start) && at.isBefore(end);
    }

    /** The part of {@code [from, to)} inside this window, if there is any. */
    public Optional<MembershipWindow> intersect(Instant from, Instant to) {
        Instant s = from.isAfter(start) ? from : start;
        Instant e = to.isBefore(end) ? to : end;
        return s.isBefore(e) ? Optional.of(new MembershipWindow(s, e)) : Optional.empty();
    }
}
