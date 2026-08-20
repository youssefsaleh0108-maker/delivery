package com.delivery.product.domain;

import java.time.DayOfWeek;
import java.time.LocalTime;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One contiguous window in which a store is open.
 *
 * <p>A row per window rather than a column per weekday, because split hours are ordinary — a coffee
 * shop open for the morning and again in the afternoon is two windows on the same day, and that
 * cannot be expressed as a single opens/closes pair.
 */
@Entity
@Table(name = "store_hours")
public class StoreHours {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    /**
     * Read-only view of the owning FK.
     *
     * <p>The column itself is written by the parent's {@code @JoinColumn}; mapping it as writable
     * here too would be two mappings competing for one column.
     */
    @Column(name = "store_id", insertable = false, updatable = false)
    private UUID storeId;

    /** ISO-8601 day number, matching {@link DayOfWeek#getValue()}: 1 = Monday .. 7 = Sunday. */
    @Column(name = "day_of_week", nullable = false)
    private short dayOfWeek;

    @Column(name = "opens_at", nullable = false)
    private LocalTime opensAt;

    @Column(name = "closes_at", nullable = false)
    private LocalTime closesAt;

    protected StoreHours() {
        // for JPA
    }

    public StoreHours(DayOfWeek day, LocalTime opensAt, LocalTime closesAt) {
        if (!closesAt.isAfter(opensAt)) {
            // Mirrors chk_hours_order. A window that wraps midnight is stored as two rows; allowing
            // it as one would put a special case in every "is it open now" comparison.
            throw new IllegalArgumentException(
                    "A window must close after it opens; split a window that crosses midnight");
        }
        this.id = UUID.randomUUID();
        this.dayOfWeek = (short) day.getValue();
        this.opensAt = opensAt;
        this.closesAt = closesAt;
    }

    /** Whether this window contains the given local time on the given ISO day. */
    public boolean covers(int isoDayOfWeek, LocalTime timeOfDay) {
        return dayOfWeek == isoDayOfWeek
                && !timeOfDay.isBefore(opensAt)
                && timeOfDay.isBefore(closesAt);
    }

    public UUID getId() {
        return id;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public DayOfWeek getDay() {
        return DayOfWeek.of(dayOfWeek);
    }

    public LocalTime getOpensAt() {
        return opensAt;
    }

    public LocalTime getClosesAt() {
        return closesAt;
    }
}
