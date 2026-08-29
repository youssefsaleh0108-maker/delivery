package com.delivery.onboarding.domain;

/**
 * Where the auto-approval position in force for a kind came from.
 *
 * <p>The distinction is not decoration. {@link #CONFIG} means nobody has ever decided this kind in
 * the portal and the deployed environment default is answering — so an ops change to that variable
 * still moves it. {@link #PORTAL} means a person set it deliberately, and from then on the
 * environment variable is ignored for that kind. A backoffice screen that showed only the on/off
 * position would let somebody turn a switch "off" that was already off, walk away believing they
 * had pinned it, and be wrong the next time the deployment changed.
 */
public enum AutoApprovalSource {

    /** No portal decision has ever been recorded for this kind; the deployment default is in force. */
    CONFIG,

    /** Somebody set this kind from the backoffice, and that decision now wins over the default. */
    PORTAL
}
