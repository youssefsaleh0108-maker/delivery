package com.delivery.product.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One customer item search, described so that it says something about a street and nothing about a
 * person (V40).
 *
 * <p>There is no column here anybody could join two rows on. No account id, no session, no device, no
 * request id, no exact pin, and the key is a random uuid rather than a sequence so even the order the
 * rows were written in is not readable. The time is truncated to the hour before it arrives, and the
 * place is the id of a delivery area — a neighbourhood shared by thousands — or nothing at all. Ask
 * this table "what did this customer look for" and there is no way to phrase the question.
 *
 * <p>That is the whole design constraint. Everything a shop wants to know — "nine people near me
 * looked for nappies and nobody within two kilometres sells them" — is a count over these rows, and a
 * count needs no identity. What it does need is that one person typing a word four times is not four
 * rows, and that is settled before a row is built ({@code SearchDemandRecorder}), in memory, on the
 * request's own account id, which never leaves the process.
 *
 * <p>Written off the request thread and never inside the search's transaction: see
 * {@code SearchDemandRecorder}. Kept for {@code delivery.demand.search-log.retention-days} and then
 * deleted ({@code SearchDemandMaintenance}).
 */
@Entity
@Table(name = "search_demand_log")
public class SearchDemandLog {

    /** The band {@link #nearestMetres} is rounded up to. See the field. */
    public static final int DISTANCE_BAND_METRES = 250;

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    /** Truncated to the hour by {@link #at}. */
    @Column(name = "searched_at", nullable = false, updatable = false)
    private Instant searchedAt;

    /**
     * The delivery area nearest the customer's pin, within the recorder's cap; null when the search
     * carried no pin or fell outside every placed area. The pin itself is never stored.
     */
    @Column(name = "area_id", updatable = false)
    private UUID areaId;

    /** The folded term, several terms joined by a space in slot order. */
    @Column(name = "term", nullable = false, updatable = false)
    private String term;

    /** How many shops answered, across every page. */
    @Column(name = "result_count", nullable = false, updatable = false)
    private int resultCount;

    /** Whether any answering shop belongs to {@link #areaId}. */
    @Column(name = "in_own_area", nullable = false, updatable = false)
    private boolean inOwnArea;

    /**
     * Metres to the nearest answering shop, rounded up to {@value #DISTANCE_BAND_METRES}; null when
     * nothing answered or the search had no pin.
     *
     * <p>Banded rather than exact: a shop's pin is public, so an exact distance to it would put the
     * customer on a circle. A band leaves a quarter-kilometre annulus and still answers the only
     * question asked of it — is the nearest shop further than two kilometres.
     */
    @Column(name = "nearest_metres", updatable = false)
    private Integer nearestMetres;

    /** The vertical the search was scoped to, when a search can be scoped; null today. */
    @Column(name = "vertical", length = 32, updatable = false)
    private String vertical;

    protected SearchDemandLog() {
    }

    /**
     * @param searchedAt truncated to the hour here rather than trusted from the caller
     * @param nearest    metres to the nearest answering shop, banded here; null when none answered
     */
    public SearchDemandLog(Instant searchedAt, UUID areaId, String term, int resultCount,
                           boolean inOwnArea, Double nearest, String vertical) {
        this.id = UUID.randomUUID();
        this.searchedAt = at(searchedAt);
        this.areaId = areaId;
        this.term = term;
        this.resultCount = Math.max(resultCount, 0);
        // A row that answered with nothing cannot have answered inside the area or at a distance:
        // the check constraint says so too, and agreeing with it here keeps a caller's mistake from
        // becoming a failed insert on a background thread nobody is watching.
        this.inOwnArea = this.resultCount > 0 && inOwnArea;
        this.nearestMetres = this.resultCount > 0 ? band(nearest) : null;
        this.vertical = vertical;
    }

    /** The hour the search fell in, in UTC. Minutes and seconds are not recorded. */
    static Instant at(Instant searchedAt) {
        return searchedAt.truncatedTo(java.time.temporal.ChronoUnit.HOURS);
    }

    /** {@code metres} rounded up to the next {@value #DISTANCE_BAND_METRES}; null stays null. */
    static Integer band(Double metres) {
        if (metres == null || metres.isNaN() || metres.isInfinite() || metres < 0) {
            return null;
        }
        long bands = (long) Math.ceil(metres / DISTANCE_BAND_METRES);
        return (int) Math.min(bands * DISTANCE_BAND_METRES, Integer.MAX_VALUE);
    }

    public UUID getId() {
        return id;
    }

    public Instant getSearchedAt() {
        return searchedAt;
    }

    public UUID getAreaId() {
        return areaId;
    }

    public String getTerm() {
        return term;
    }

    public int getResultCount() {
        return resultCount;
    }

    public boolean isInOwnArea() {
        return inOwnArea;
    }

    public Integer getNearestMetres() {
        return nearestMetres;
    }

    public String getVertical() {
        return vertical;
    }
}
