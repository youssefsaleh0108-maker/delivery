package com.delivery.notifications.link;

import java.util.Locale;
import java.util.Optional;

/**
 * The kinds of screen a notification is allowed to point at.
 *
 * <p>A closed set rather than a free-text string, because the alternative is a template author
 * inventing a target the app has no route for — which fails silently on the device, at the one
 * moment the customer is actively trying to act on the notification. A new target is a code change
 * here plus a migration to widen the CHECK constraint, and that friction is the point: it forces
 * the app and the platform to agree that the route exists before a notification can send anyone to
 * it.
 *
 * <p>The slug is deliberately the plural the mobile app already routes on. Push Connector has been
 * synthesising {@code delivery://orders/<id>} as a fallback for order pushes since before this
 * existed, so ORDER resolving to {@code orders} means the link this service now sends explicitly is
 * byte-identical to the one the app has been receiving — no app release is needed to adopt it, and
 * there is never a window where two spellings of the same link are in flight.
 */
public enum NotificationLinkTarget {

    /** One order's detail screen. By far the commonest target — every {@code order.*} event. */
    ORDER("orders", "orderId"),

    /** A chat thread, e.g. customer to rider. */
    CONVERSATION("conversations", "conversationId"),

    /** A rider or merchant application under review. */
    APPLICATION("applications", "applicationId"),

    /** One earnings statement for a rider. */
    EARNINGS("earnings", "statementId"),

    /**
     * The account screen itself. The only target with no id: "your password was changed" points at
     * a screen, not at a record, and inventing an id for it would make every consumer handle a
     * value that means nothing.
     */
    ACCOUNT("account", null);

    private final String slug;
    private final String idPlaceholder;

    NotificationLinkTarget(String slug, String idPlaceholder) {
        this.slug = slug;
        this.idPlaceholder = idPlaceholder;
    }

    /** The path segment used in the canonical form, matching the app's existing routes. */
    public String slug() {
        return slug;
    }

    /**
     * Which template placeholder holds this target's id.
     *
     * <p>Lets a template say only <em>what kind of thing</em> it points at while the id comes from
     * the event that triggered it. Storing the id in the template row instead would be storing a
     * per-event value in a per-event-type row — the same template serves every order there is.
     *
     * @return null for {@link #ACCOUNT}, which takes no id
     */
    public String idPlaceholder() {
        return idPlaceholder;
    }

    public boolean takesId() {
        return idPlaceholder != null;
    }

    /**
     * Parses a stored or caller-supplied target name.
     *
     * <p>Returns empty rather than throwing: the input is a database column a human edits and a
     * field on a request body, so an unrecognised value is a data problem to skip past, not an
     * exception to take a notification down with.
     */
    public static Optional<NotificationLinkTarget> of(String name) {
        if (name == null || name.isBlank()) {
            return Optional.empty();
        }
        try {
            return Optional.of(valueOf(name.trim().toUpperCase(Locale.ROOT)));
        } catch (IllegalArgumentException e) {
            return Optional.empty();
        }
    }

    /** Resolves by slug, so a canonical string can be turned back into a typed target. */
    static Optional<NotificationLinkTarget> bySlug(String slug) {
        if (slug == null) {
            return Optional.empty();
        }
        for (NotificationLinkTarget target : values()) {
            if (target.slug.equals(slug)) {
                return Optional.of(target);
            }
        }
        return Optional.empty();
    }
}
