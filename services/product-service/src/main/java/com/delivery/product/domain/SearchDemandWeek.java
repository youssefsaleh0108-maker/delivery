package com.delivery.product.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One term an area looked for in one week and did not find nearby (V40).
 *
 * <p>Written by the weekly roll-up, read by the merchant's Demand Radar and by the digest. A term is
 * only ever written once it has cleared the floor of distinct searches, so this table holds market
 * signals and never a single person's errand — and because the floor is applied when the row is made
 * rather than when it is read, no reader can be written that forgets it.
 *
 * <p>{@link #searches} is exact here and never served exact: the API turns it into a band ("about
 * ten"). A shop deciding what to stock needs the order of magnitude, and a precise count invites
 * subtraction — a merchant comparing weeks could otherwise watch one household's habits change.
 */
@Entity
@Table(name = "search_demand_week")
public class SearchDemandWeek {

    /** Why a term counts as unmet. */
    public enum Kind {
        /** Every search for it answered with no shop at all. */
        NONE,
        /** It answered, but only with shops further than the far threshold. */
        FAR
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    /** Monday 00:00 in the platform's zone, as the instant it was. */
    @Column(name = "week_start", nullable = false, updatable = false)
    private Instant weekStart;

    @Column(name = "area_id", nullable = false, updatable = false)
    private UUID areaId;

    @Column(name = "term", nullable = false, updatable = false)
    private String term;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, length = 16, updatable = false)
    private Kind kind;

    @Column(name = "searches", nullable = false)
    private int searches;

    @Column(name = "rank", nullable = false)
    private int rank;

    @Column(name = "computed_at", nullable = false)
    private Instant computedAt;

    protected SearchDemandWeek() {
    }

    public SearchDemandWeek(Instant weekStart, UUID areaId, String term, Kind kind, int searches,
                            int rank, Instant computedAt) {
        this.id = UUID.randomUUID();
        this.weekStart = weekStart;
        this.areaId = areaId;
        this.term = term;
        this.kind = kind;
        this.searches = searches;
        this.rank = rank;
        this.computedAt = computedAt;
    }

    public UUID getId() {
        return id;
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

    public Kind getKind() {
        return kind;
    }

    public int getSearches() {
        return searches;
    }

    public int getRank() {
        return rank;
    }

    public Instant getComputedAt() {
        return computedAt;
    }
}
