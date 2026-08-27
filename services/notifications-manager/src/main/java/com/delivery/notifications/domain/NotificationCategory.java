package com.delivery.notifications.domain;

import java.util.Locale;
import java.util.Optional;

/**
 * The buckets a user can turn on and off in the settings screen.
 *
 * <p>Coarse on purpose. A preference per event type would give a customer thirty switches and no
 * idea which one stops the thing that is bothering them; four buckets are what the settings screen
 * shows and what somebody can reason about. The cost is that a category is all-or-nothing, which is
 * the right trade for a delivery app — nobody wants "tell me when it is picked up but not when it
 * is delivered".
 */
public enum NotificationCategory {

    /** Progress on an order the user placed, is preparing, or is delivering. */
    ORDER_UPDATES(true, false),

    /** Messages between a customer, a rider and a merchant. */
    CHAT(true, false),

    /**
     * Marketing. <strong>Off unless the user turns it on</strong>, and that default is the whole
     * point rather than a detail: consent to be marketed at is not implied by signing up to have
     * food delivered. Opt-out-by-default is also what keeps this side of the platform defensible
     * under consent rules, and flipping it later is a one-word change that nobody would notice in
     * review — so the reasoning lives here.
     */
    PROMOTIONS(false, false),

    /**
     * Security and account integrity: one-time codes, password and email changes, suspensions,
     * application decisions.
     *
     * <p>{@code alwaysDelivered}, so no preference can suppress it. A user who has silenced
     * marketing has not asked to stop being told their password was changed, and a platform that
     * let a settings toggle swallow that would be handing an attacker a way to work unobserved. The
     * table is not even consulted for this category — there is no row that could be wrong.
     */
    ACCOUNT(true, true);

    private final boolean defaultEnabled;
    private final boolean alwaysDelivered;

    NotificationCategory(boolean defaultEnabled, boolean alwaysDelivered) {
        this.defaultEnabled = defaultEnabled;
        this.alwaysDelivered = alwaysDelivered;
    }

    /**
     * What this category does for a user who has never opened the settings screen.
     *
     * <p>Held in code rather than seeded as a row per user per category per channel. Seeding would
     * mean a backfill for every existing user, a row to write the moment anyone signs up, and a
     * silent behaviour change for everybody if a default is ever revised. Storing only the
     * deviations means the absence of a row is a fact in itself: this user has not expressed a
     * preference here.
     */
    public boolean defaultEnabled() {
        return defaultEnabled;
    }

    /** True when no preference may suppress this category. See {@link #ACCOUNT}. */
    public boolean alwaysDelivered() {
        return alwaysDelivered;
    }

    /**
     * Which bucket an event type falls in.
     *
     * <p>Derived from the event type's namespace rather than stored on the template row. Event types
     * are already namespaced ({@code order.placed.merchant}, {@code onboarding.verification}), so
     * the category is a fact about the event and duplicating it into the template table would let
     * two rows for one event disagree about whether the customer had opted out.
     *
     * <p><strong>An unrecognised type is ACCOUNT, which is to say undroppable.</strong> Fail-safe
     * here means delivering: a new event type nobody remembered to classify sending one message the
     * user could have muted is a small, visible annoyance, while the same oversight silently
     * swallowing a security notice is not recoverable and nobody finds out.
     */
    public static NotificationCategory forEventType(String eventType) {
        if (eventType == null) {
            return ACCOUNT;
        }
        String type = eventType.trim().toLowerCase(Locale.ROOT);
        if (type.startsWith("order.")) {
            return ORDER_UPDATES;
        }
        if (type.startsWith("chat.") || type.startsWith("conversation.")
                || type.startsWith("message.")) {
            return CHAT;
        }
        if (type.startsWith("marketing.") || type.startsWith("promotion.")
                || type.startsWith("promo.")) {
            return PROMOTIONS;
        }
        return ACCOUNT;
    }

    /**
     * Parses a caller-supplied category name.
     *
     * <p>Empty rather than an exception, so the controller can answer with its own wording instead
     * of letting a user-supplied string reach an error body.
     */
    public static Optional<NotificationCategory> of(String name) {
        if (name == null || name.isBlank()) {
            return Optional.empty();
        }
        try {
            return Optional.of(valueOf(name.trim().toUpperCase(Locale.ROOT)));
        } catch (IllegalArgumentException e) {
            return Optional.empty();
        }
    }
}
