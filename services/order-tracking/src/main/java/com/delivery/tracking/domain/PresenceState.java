package com.delivery.tracking.domain;

/**
 * Whether a rider is actually reachable right now — the declaration in {@link DutyState} checked
 * against whether their phone is still talking to us.
 *
 * <p>Computed at read time from the last ping, never stored. That is the whole point: a handset
 * that runs out of battery, loses signal in a car park or gets force-quit does not send a message
 * saying so. The only evidence that a rider is still there is a recent fix, so the absence of one
 * has to be what changes the answer.
 *
 * <p>{@link #STALE} is a separate value rather than being folded into {@code OFF_DUTY} because the
 * two need different handling. An off-duty rider has finished; a stale one thinks they are working
 * and something is wrong — dispatch must not give them a job, and a human should probably call
 * them. Collapsing the two would make a dead phone indistinguishable from a shift ending.
 */
public enum PresenceState {

    /** Declared on duty and pinged recently enough to be believed. */
    ON_DUTY,

    /** Declared on duty, but the last fix is older than the presence window. Not dispatchable. */
    STALE,

    /** Declared off duty. */
    OFF_DUTY
}
