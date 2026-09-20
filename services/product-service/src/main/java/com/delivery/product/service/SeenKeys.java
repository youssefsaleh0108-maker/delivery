package com.delivery.product.service;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.time.Instant;
import java.util.HexFormat;
import java.util.Optional;
import java.util.UUID;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Turns a person into a number that is only ever equal to itself.
 *
 * <p>The digest's floor has to count people, and this service is built so that it cannot hold one.
 * The way out is a keyed hash of what a person asked for rather than of who they are:
 *
 * <pre>seen_key = HMAC-SHA256(secret, "v1" | account | area | term | week)</pre>
 *
 * <p>The same person asking again for the same thing, in the same neighbourhood, in the same week
 * produces the same value — which is the whole point, because that is how five rows mean five people
 * rather than five searches. Everything else about it is what it refuses to be:
 *
 * <ul>
 *   <li><strong>not reversible.</strong> Without the secret, no account id can be turned into a key
 *       and no key into an account id. A dump of {@code search_demand_seen}, a backup, a restored
 *       snapshot: all of them are a column of numbers;</li>
 *   <li><strong>not joinable across terms.</strong> The term and the area are inside the HMAC, so
 *       one person's two searches leave two values with nothing in common. There is no pseudonym
 *       here that follows somebody from one word to the next, which is exactly what a pseudonym
 *       would have been;</li>
 *   <li><strong>not a lookup.</strong> Somebody holding the secret could compute the key for an
 *       account they already suspect and a term they already guessed, and ask whether that row
 *       exists. That is why the secret is held the way the platform holds its other secrets — in the
 *       environment, from a Secret, never in the repository and never in this database beside the
 *       values it computed.</li>
 * </ul>
 *
 * <p><strong>With no secret, nothing is published.</strong> {@link #available()} is false, no row is
 * written, and the roll-up refuses to run rather than falling back to counting searches
 * ({@code UnmetDemand}). The weak floor is the thing this replaces; quietly restoring it when a
 * variable is missing would be the worst of both.
 *
 * <p><strong>Rotation.</strong> {@link #keyId()} is a fingerprint <em>derived from</em> the secret,
 * not the secret, and the roll-up counts only rows carrying the current one. A new secret therefore
 * reads as "nobody has asked yet", so a rotation can only under-publish — never count one person
 * twice under two keys. Rotate just after a Monday digest: the finished week has been sent, and the
 * week in progress starts its count again.
 */
@Component
public class SeenKeys {

    private static final Logger log = LoggerFactory.getLogger(SeenKeys.class);

    private static final String ALGORITHM = "HmacSHA256";

    /** The shape of the message, so a later change to it cannot silently collide with this one. */
    private static final String VERSION = "v1";

    /** What the fingerprint is the HMAC of. A constant, so the same secret always names itself. */
    private static final String KEY_ID_MESSAGE = "search-demand-seen/key-id";

    /** How much of the fingerprint is kept. Enough to tell two secrets apart, and no more. */
    private static final int KEY_ID_LENGTH = 16;

    /**
     * The shortest secret that may be configured. Refused at start-up rather than clamped or
     * accepted: a floor resting on a four-character secret is a floor anybody can compute their way
     * past, and it would look exactly like a working one.
     */
    static final int MIN_SECRET_LENGTH = 24;

    private final byte[] secret;
    private final String keyId;

    public SeenKeys(@Value("${delivery.demand.search-log.seen-secret:}") String secret) {
        String configured = secret == null ? "" : secret.trim();
        if (configured.isEmpty()) {
            // Not an error: an environment that has not been given the secret yet should start, serve
            // searches and record them. It simply publishes nothing, and says so once, here.
            log.warn("No demand-seen secret is set (DEMAND_SEEN_SECRET), so the weekly demand digest "
                    + "will not roll up or send anything: its floor counts distinct people and "
                    + "cannot be applied without it. Searches are still recorded.");
            this.secret = null;
            this.keyId = null;
            return;
        }
        if (configured.length() < MIN_SECRET_LENGTH) {
            throw new IllegalArgumentException("delivery.demand.search-log.seen-secret must be at "
                    + "least " + MIN_SECRET_LENGTH + " characters. It is what stops the digest's "
                    + "floor being computed past, so a short one is worse than none.");
        }
        this.secret = configured.getBytes(StandardCharsets.UTF_8);
        this.keyId = hex(hmac(KEY_ID_MESSAGE)).substring(0, KEY_ID_LENGTH);
    }

    /** Whether a secret was configured. False means nothing is counted and nothing is published. */
    public boolean available() {
        return secret != null;
    }

    /**
     * The fingerprint of the current secret, or null when there is none.
     *
     * <p>Safe to store and to log: it is an HMAC of a fixed public string under the secret, so it
     * names the key without carrying any of it.
     */
    public String keyId() {
        return keyId;
    }

    /**
     * The value that stands for "this person asked for this term, in this area, this week".
     *
     * @return empty when there is no secret, or when any part of the question is missing — a search
     *         with no area is never reported to anybody, so it needs no row
     */
    public Optional<String> keyFor(String accountId, UUID areaId, String term, Instant weekStart) {
        if (!available() || accountId == null || accountId.isBlank() || areaId == null
                || term == null || term.isBlank() || weekStart == null) {
            return Optional.empty();
        }
        // Newline-separated, and no part of it can contain a newline: an account id is a Keycloak
        // sub, an area is a uuid, a week is an instant, and a folded search term is one line of
        // words. So two different questions cannot fold into one message.
        String message = VERSION + '\n' + accountId + '\n' + areaId + '\n' + term + '\n'
                + weekStart.toEpochMilli();
        return Optional.of(hex(hmac(message)));
    }

    private byte[] hmac(String message) {
        try {
            // A Mac per call rather than a shared one: Mac is not thread-safe, and this is cheap
            // beside the insert it belongs to.
            Mac mac = Mac.getInstance(ALGORITHM);
            mac.init(new SecretKeySpec(secret, ALGORITHM));
            return mac.doFinal(message.getBytes(StandardCharsets.UTF_8));
        } catch (GeneralSecurityException e) {
            // HmacSHA256 is required of every JRE, so this is not a runtime condition to handle.
            throw new IllegalStateException("This JVM cannot compute " + ALGORITHM, e);
        }
    }

    private static String hex(byte[] bytes) {
        return HexFormat.of().formatHex(bytes);
    }
}
