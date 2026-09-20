package com.delivery.product.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * "Somebody has already asked for this here, this week" — one row per person per area per term per
 * week, and no way to tell which person (V40).
 *
 * <p>This exists because the floor has to count people. Counting log rows counts searches, and one
 * household searching for the same thing on five evenings is five searches: a floor of five that one
 * household can clear is not a floor, and a merchant could clear it for a neighbour's term by
 * searching four times themselves.
 *
 * <p>What is stored is {@code HMAC-SHA256(secret, "v1" | account | area | term | week)} in hex
 * ({@code SeenKeys}), under a secret that lives in the environment and never in the repository, this
 * database or an event. So the value is not reversible into an account, and — because the term is
 * inside the HMAC — the same person's two terms leave two unrelated values, which is what stops this
 * table becoming the "everything this customer searched for" index that {@link SearchDemandLog}
 * refuses to be. The only question ever asked of it is how many rows a (week, area, term) has.
 *
 * <p>Kept only as long as the week it bounds and the one after, which is as far back as the roll-up
 * ever recomputes, and deleted by the same retention job as the log.
 */
@Entity
@Table(name = "search_demand_seen")
public class SearchDemandSeen {

    /** The HMAC, in hex. Sixty-four characters of SHA-256, and the whole of the primary key. */
    @Id
    @Column(name = "seen_key", nullable = false, length = 64, updatable = false)
    private String seenKey;

    /**
     * A fingerprint of the secret that computed {@link #seenKey}, never the secret. The roll-up
     * counts only the current one, so a rotation reads as "nobody has asked yet" rather than as the
     * same person twice.
     */
    @Column(name = "key_id", nullable = false, length = 32, updatable = false)
    private String keyId;

    /** Monday 00:00 in the platform's zone, of the week the search fell in. */
    @Column(name = "week_start", nullable = false, updatable = false)
    private Instant weekStart;

    @Column(name = "area_id", nullable = false, updatable = false)
    private UUID areaId;

    /** The folded term, as {@link SearchDemandLog} holds it. */
    @Column(name = "term", nullable = false, updatable = false)
    private String term;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected SearchDemandSeen() {
    }

    public SearchDemandSeen(String seenKey, String keyId, Instant weekStart, UUID areaId, String term,
                            Instant createdAt) {
        this.seenKey = seenKey;
        this.keyId = keyId;
        this.weekStart = weekStart;
        this.areaId = areaId;
        this.term = term;
        this.createdAt = createdAt;
    }

    public String getSeenKey() {
        return seenKey;
    }

    public String getKeyId() {
        return keyId;
    }

    public Instant getWeekStart() {
        return weekStart;
    }

    public UUID getAreaId() {
        return areaId;
    }

    public String getTerm() {
        return term;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
