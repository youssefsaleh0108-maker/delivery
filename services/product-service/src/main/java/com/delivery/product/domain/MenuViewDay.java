package com.delivery.product.domain;

import java.io.Serializable;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.Objects;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

/**
 * How many times one shop's menu was opened, on one of its days, in one part of that day, by one
 * way in.
 *
 * <p><strong>This is a counter, not a visit.</strong> The distinction is the whole of V44's privacy
 * argument and it is worth restating where the code is: there is no row per reader here and there
 * never was one. Nothing in this table is a sequence, so nothing about it can be put back into the
 * order people arrived in; nothing in it narrows to a person, so nothing can be followed between
 * two rows. Two people and one person who looked twice are indistinguishable here permanently, by
 * construction rather than by care.
 *
 * <p>It holds no timestamp at all. The finest time it knows is {@link Part}, four to a day, decided
 * at flush time in the shop's own zone and then discarded — see {@link MenuViewDay#partOf}.
 *
 * <p>What a number here means is narrower than it looks, and {@code MenuInsights} is responsible
 * for never letting the screen overstate it: it counts requests this service answered, so a reader
 * served from a browser or CDN cache is not in it, and a link preview is.
 */
@Entity
@Table(name = "menu_view_day")
@IdClass(MenuViewDay.Key.class)
public class MenuViewDay {

    /**
     * A quarter of the shop's day.
     *
     * <p>Four, and not twenty-four, and the reason is not tidiness. A shop shown "one open at 19:00
     * on Tuesday" has been told about a person; that it takes a quiet shop for that sentence to be
     * true is not a defence, because quiet shops are most shops. {@code search_demand_log} can
     * afford to keep an hour because its floor counts distinct PEOPLE, through a keyed marker it
     * derives from the account behind each search. An anonymous page open has no account behind it,
     * so there is nothing here to count people with — and the granularity has to carry the weight
     * the people-floor carries there.
     *
     * <p>Declared in the order a day runs, so a chart drawn from {@code values()} reads left to
     * right without the caller sorting anything.
     */
    public enum Part {
        MORNING(LocalTime.of(5, 0)),
        MIDDAY(LocalTime.of(11, 0)),
        EVENING(LocalTime.of(17, 0)),
        NIGHT(LocalTime.of(23, 0));

        private final LocalTime from;

        Part(LocalTime from) {
            this.from = from;
        }

        /** When this part of the day starts, in the shop's own zone. */
        public LocalTime from() {
            return from;
        }
    }

    /**
     * How the reader's address said they arrived — as far as the URL itself says, and no further.
     *
     * <p>There is deliberately no {@code QR} here. A shop's counter code ({@code /s/{slug}/qr.png})
     * encodes the page's plain address with nothing added to it, so a phone that scanned the sign
     * and a thumb that tapped a link in a chat send the identical request. Only a table card's code
     * carries a marker, and only because it had to carry the table number anyway. A "scans" figure
     * would be a number the platform cannot compute, which is a different thing from a number it
     * does not have yet.
     */
    public enum Source {
        /** The address carried no table parameter: a link, a sign, a bookmark, a crawler. */
        LINK,
        /** The address carried {@code ?t=N} — a code printed on one of the shop's tables. */
        TABLE
    }

    /**
     * Which part of a shop's day a local time falls in.
     *
     * <p>The one place the mapping lives. NIGHT wraps midnight, which is why this walks the parts
     * backwards rather than comparing ranges: 23:30 and 02:00 are the same part of the same
     * trading night, and a shop that closes at one in the morning would otherwise read its last
     * hour as the next day's first.
     */
    public static Part partOf(LocalTime local) {
        if (local.isBefore(Part.MORNING.from())) {
            return Part.NIGHT;
        }
        Part found = Part.MORNING;
        for (Part part : Part.values()) {
            if (!local.isBefore(part.from())) {
                found = part;
            }
        }
        return found;
    }

    @Id
    @Column(name = "store_id", nullable = false, updatable = false)
    private UUID storeId;

    /** The calendar day in the shop's own zone. The merchant's Tuesday, not UTC's. */
    @Id
    @Column(name = "viewed_on", nullable = false, updatable = false)
    private LocalDate viewedOn;

    @Id
    @Enumerated(EnumType.STRING)
    @Column(name = "day_part", nullable = false, updatable = false, length = 8)
    private Part dayPart;

    @Id
    @Enumerated(EnumType.STRING)
    @Column(name = "source", nullable = false, updatable = false, length = 8)
    private Source source;

    @Column(name = "views", nullable = false)
    private int views;

    protected MenuViewDay() {
        // for JPA
    }

    /**
     * A counter as it is read back, and as a test writes one.
     *
     * <p>Note that nothing in the service builds one of these in order to save it:
     * {@code MenuViewDayRepository.add} is the only write path to this table, because the write is
     * an addition to a row that may not exist and that is one statement in Postgres and a race in
     * JPA. This constructor exists so a test can state what the table holds without going through
     * a database to say it.
     */
    public MenuViewDay(UUID storeId, LocalDate viewedOn, Part dayPart, Source source, int views) {
        this.storeId = storeId;
        this.viewedOn = viewedOn;
        this.dayPart = dayPart;
        this.source = source;
        this.views = views;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public LocalDate getViewedOn() {
        return viewedOn;
    }

    public Part getDayPart() {
        return dayPart;
    }

    public Source getSource() {
        return source;
    }

    public int getViews() {
        return views;
    }

    /** The composite key, which is the bucket itself — there is no surrogate id to be a sequence. */
    public static class Key implements Serializable {

        private UUID storeId;
        private LocalDate viewedOn;
        private MenuViewDay.Part dayPart;
        private MenuViewDay.Source source;

        public Key() {
        }

        public Key(UUID storeId, LocalDate viewedOn, MenuViewDay.Part dayPart,
                   MenuViewDay.Source source) {
            this.storeId = storeId;
            this.viewedOn = viewedOn;
            this.dayPart = dayPart;
            this.source = source;
        }

        @Override
        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Key key)) {
                return false;
            }
            return Objects.equals(storeId, key.storeId)
                    && Objects.equals(viewedOn, key.viewedOn)
                    && dayPart == key.dayPart
                    && source == key.source;
        }

        @Override
        public int hashCode() {
            return Objects.hash(storeId, viewedOn, dayPart, source);
        }
    }
}
