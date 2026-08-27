package com.delivery.notifications.link;

import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Where a notification points, as a typed pair rather than a string somebody has to parse.
 *
 * <p><strong>No hostname, deliberately.</strong> The canonical form is
 * {@code delivery://orders/<id>} — a private scheme whose authority segment names the <em>kind</em>
 * of thing being opened, not a server. Baking a hostname in ({@code https://app.example.com/...})
 * has already bitten this project once: the host moved, and every notification already sitting in a
 * device's tray, in a queue backlog, or in the notification log kept pointing at the old one. A
 * link is a routing instruction to the app, and an app that has just been pointed at a different
 * environment must not have to re-resolve links it was handed yesterday. Anything that genuinely
 * needs a web URL — an email's "view your order" button — composes one at render time from the
 * environment's own base URL, where a redeploy fixes it.
 *
 * <p>The pair travels alongside the canonical string in command metadata rather than instead of it.
 * The string is what the app routes on today (Push Connector and the FCM data payload already carry
 * a {@code deepLink} key); the typed pair is what anything downstream should branch on, so no
 * consumer ends up splitting a URL on slashes to work out that this was an order.
 *
 * @param target what kind of screen to open
 * @param id     which one, or null for a target that takes none (see
 *               {@link NotificationLinkTarget#ACCOUNT})
 */
public record NotificationLink(NotificationLinkTarget target, String id) {

    /** The app's private scheme. Registered by the mobile client; never resolved over a network. */
    public static final String SCHEME = "delivery";

    /** Metadata key for the typed target name, e.g. {@code ORDER}. */
    public static final String METADATA_TARGET = "linkTarget";

    /** Metadata key for the target's id. Absent when the target takes none. */
    public static final String METADATA_ID = "linkId";

    /**
     * Metadata key for the canonical string.
     *
     * <p>Named {@code deepLink} because that is the key Push Connector already writes and the app
     * already reads. Choosing a new name would have meant the connector's own fallback and this
     * service's explicit link arriving under two keys, with the app picking whichever it knew about.
     */
    public static final String METADATA_CANONICAL = "deepLink";

    /**
     * Ids that are safe to concatenate into the canonical form.
     *
     * <p>Ids reach this class from event payloads and from template placeholders filled with order
     * data, which is to say from somewhere a customer can influence. A value containing a slash or a
     * space would change which route the app resolves — a link that says it opens an order and does
     * not. Rejecting rather than escaping, because every legitimate id on this platform is a UUID or
     * a short opaque token and none of them need a character outside this set.
     */
    private static final Pattern SAFE_ID = Pattern.compile("[A-Za-z0-9_.:-]{1,128}");

    public NotificationLink {
        if (target == null) {
            throw new IllegalArgumentException("a link must name what it points at");
        }
        id = id == null || id.isBlank() ? null : id.trim();
        if (id != null && !SAFE_ID.matcher(id).matches()) {
            // The offending value is not repeated in the message: it is untrusted text, and this
            // message can surface in a log line or an API error body.
            throw new IllegalArgumentException("link id contains characters that are not routable");
        }
        if (id != null && !target.takesId()) {
            throw new IllegalArgumentException(target + " links take no id");
        }
        if (id == null && target.takesId()) {
            throw new IllegalArgumentException(target + " links need an id");
        }
    }

    public static NotificationLink toOrder(UUID orderId) {
        return new NotificationLink(NotificationLinkTarget.ORDER, orderId.toString());
    }

    /**
     * Builds a link if the id is present and usable, and nothing at all otherwise.
     *
     * <p>A missing or malformed id is not worth failing a notification over: the message still says
     * something useful, and a notification that does not send is strictly worse for the customer
     * than one that opens the app's home screen.
     */
    public static Optional<NotificationLink> of(NotificationLinkTarget target, String id) {
        if (target == null) {
            return Optional.empty();
        }
        try {
            return Optional.of(new NotificationLink(target, id));
        } catch (IllegalArgumentException e) {
            return Optional.empty();
        }
    }

    /** {@code delivery://orders/6f1c…} — or {@code delivery://account} for a target with no id. */
    public String canonical() {
        return SCHEME + "://" + target.slug() + (id == null ? "" : "/" + id);
    }

    /**
     * Reads a canonical string back into a typed link.
     *
     * <p>Deliberately hand-parsed rather than run through {@link java.net.URI}: under a private
     * scheme the segment after {@code //} is an authority to URI, so {@code getPath()} returns
     * {@code /<id>} and {@code getHost()} sometimes returns null for perfectly valid slugs. Splitting
     * the string is both shorter and free of that trap.
     */
    public static Optional<NotificationLink> parse(String canonical) {
        if (canonical == null) {
            return Optional.empty();
        }
        String prefix = SCHEME + "://";
        if (!canonical.startsWith(prefix)) {
            return Optional.empty();
        }
        String rest = canonical.substring(prefix.length());
        int slash = rest.indexOf('/');
        String slug = slash < 0 ? rest : rest.substring(0, slash);
        String id = slash < 0 ? null : rest.substring(slash + 1);
        return NotificationLinkTarget.bySlug(slug)
                .flatMap(target -> of(target, id));
    }

    /** Writes the typed pair and the canonical string into a command's metadata map. */
    public void writeTo(Map<String, String> metadata) {
        metadata.put(METADATA_TARGET, target.name());
        if (id != null) {
            metadata.put(METADATA_ID, id);
        }
        metadata.put(METADATA_CANONICAL, canonical());
    }

    /**
     * Recovers a link from command metadata.
     *
     * <p>Prefers the typed pair and falls back to parsing the canonical string, so a command written
     * by an older build — one that only ever set {@code deepLink} — still yields a typed link rather
     * than nothing.
     */
    public static Optional<NotificationLink> fromMetadata(Map<String, String> metadata) {
        if (metadata == null) {
            return Optional.empty();
        }
        Optional<NotificationLink> typed = NotificationLinkTarget.of(metadata.get(METADATA_TARGET))
                .flatMap(target -> of(target, metadata.get(METADATA_ID)));
        return typed.isPresent() ? typed : parse(metadata.get(METADATA_CANONICAL));
    }
}
