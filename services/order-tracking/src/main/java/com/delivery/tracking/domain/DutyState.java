package com.delivery.tracking.domain;

/**
 * What a rider has told the platform about their own availability.
 *
 * <p>Deliberately only two values, and deliberately not the same type as {@link PresenceState}.
 * This is a declaration; presence is a fact. A rider who declared ON_DUTY and then dropped down a
 * lift shaft is still {@code ON_DUTY} here and is <em>not</em> on duty as far as anything that
 * dispatches work is concerned — see {@link PresenceState} for where those two part company.
 */
public enum DutyState {

    /** The rider says they are available for work. */
    ON_DUTY,

    /** The rider says they are not. Also the state every rider starts in. */
    OFF_DUTY
}
