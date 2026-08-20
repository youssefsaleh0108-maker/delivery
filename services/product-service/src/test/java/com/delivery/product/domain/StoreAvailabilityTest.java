package com.delivery.product.domain;

import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.List;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * What a store's card says, and when.
 *
 * <p>Availability is derived from the clock on every read, so it is the one piece of storefront
 * logic that cannot be checked by looking at a row. Every branch is pinned here at a chosen instant
 * rather than left to be noticed at the wrong hour in production.
 */
class StoreAvailabilityTest {

    /** A Wednesday, so weekday arithmetic has somewhere to go wrong in both directions. */
    private static final LocalDate WEDNESDAY = LocalDate.of(2026, 8, 12);

    private static Instant utc(int hour, int minute) {
        return ZonedDateTime.of(WEDNESDAY, LocalTime.of(hour, minute), ZoneId.of("UTC")).toInstant();
    }

    private static Store storeOpen(LocalTime from, LocalTime to) {
        Store store = new Store("merchant-1", "Beirut Grill", Store.Vertical.RESTAURANT);
        store.replaceHours(everyDay(from, to));
        store.publish();
        return store;
    }

    private static List<StoreHours> everyDay(LocalTime from, LocalTime to) {
        return java.util.Arrays.stream(DayOfWeek.values())
                .map(day -> new StoreHours(day, from, to))
                .toList();
    }

    @Nested
    @DisplayName("the four states")
    class States {

        @Test
        void open_well_inside_the_window() {
            Store store = storeOpen(LocalTime.of(8, 0), LocalTime.of(23, 0));

            assertThat(store.availabilityAt(utc(12, 0))).isEqualTo(Store.Availability.OPEN);
        }

        @Test
        void closing_soon_within_the_last_half_hour() {
            Store store = storeOpen(LocalTime.of(8, 0), LocalTime.of(23, 0));

            assertThat(store.availabilityAt(utc(22, 31))).isEqualTo(Store.Availability.CLOSING_SOON);
        }

        @Test
        void the_closing_soon_boundary_is_inclusive_at_exactly_thirty_minutes() {
            Store store = storeOpen(LocalTime.of(8, 0), LocalTime.of(23, 0));

            assertThat(store.availabilityAt(utc(22, 30))).isEqualTo(Store.Availability.CLOSING_SOON);
            // One minute earlier is still simply open.
            assertThat(store.availabilityAt(utc(22, 29))).isEqualTo(Store.Availability.OPEN);
        }

        @Test
        void closed_outside_the_window() {
            Store store = storeOpen(LocalTime.of(8, 0), LocalTime.of(23, 0));

            assertThat(store.availabilityAt(utc(7, 59))).isEqualTo(Store.Availability.CLOSED);
            assertThat(store.availabilityAt(utc(23, 0))).isEqualTo(Store.Availability.CLOSED);
        }

        @Test
        void busy_when_the_kitchen_is_behind() {
            Store store = storeOpen(LocalTime.of(8, 0), LocalTime.of(23, 0));
            store.markBusyUntil(utc(12, 20));

            assertThat(store.availabilityAt(utc(12, 0))).isEqualTo(Store.Availability.BUSY);
        }
    }

    @Nested
    @DisplayName("precedence between the states")
    class Precedence {

        /**
         * A shut shop that is also "behind on orders" is a nonsense card. Closed has to win, and it
         * is the ordering most likely to be broken by someone reordering the checks.
         */
        @Test
        void closed_beats_busy() {
            Store store = storeOpen(LocalTime.of(8, 0), LocalTime.of(23, 0));
            store.markBusyUntil(utc(6, 0));

            assertThat(store.availabilityAt(utc(3, 0))).isEqualTo(Store.Availability.CLOSED);
        }

        /** The more urgent operational warning is the one the customer needs first. */
        @Test
        void busy_beats_closing_soon() {
            Store store = storeOpen(LocalTime.of(8, 0), LocalTime.of(23, 0));
            store.markBusyUntil(utc(23, 0));

            // 22:45 would read as CLOSING_SOON on its own.
            assertThat(store.availabilityAt(utc(22, 45))).isEqualTo(Store.Availability.BUSY);
        }

        /** The flag is a timestamp precisely so it cannot be left switched on overnight. */
        @Test
        void a_busy_flag_in_the_past_no_longer_applies() {
            Store store = storeOpen(LocalTime.of(8, 0), LocalTime.of(23, 0));
            store.markBusyUntil(utc(11, 0));

            assertThat(store.availabilityAt(utc(11, 1))).isEqualTo(Store.Availability.OPEN);
        }

        @Test
        void clearing_busy_takes_effect_immediately() {
            Store store = storeOpen(LocalTime.of(8, 0), LocalTime.of(23, 0));
            store.markBusyUntil(utc(20, 0));
            assertThat(store.availabilityAt(utc(12, 0))).isEqualTo(Store.Availability.BUSY);

            store.clearBusy();

            assertThat(store.availabilityAt(utc(12, 0))).isEqualTo(Store.Availability.OPEN);
        }
    }

    @Nested
    @DisplayName("lifecycle status")
    class Lifecycle {

        @Test
        void a_draft_store_is_closed_whatever_its_hours_say() {
            Store store = new Store("merchant-1", "Not launched yet", Store.Vertical.GROCERY);
            store.replaceHours(everyDay(LocalTime.of(0, 0), LocalTime.of(23, 59)));
            // deliberately not published

            assertThat(store.availabilityAt(utc(12, 0))).isEqualTo(Store.Availability.CLOSED);
        }

        @Test
        void a_suspended_store_is_closed() {
            Store store = storeOpen(LocalTime.of(0, 0), LocalTime.of(23, 59));
            store.suspend();

            assertThat(store.availabilityAt(utc(12, 0))).isEqualTo(Store.Availability.CLOSED);
        }

        /** Availability is derived entirely from hours, so publishing without them lists a shop
         *  that could never be open. */
        @Test
        void publishing_without_hours_is_refused() {
            Store store = new Store("merchant-1", "No hours", Store.Vertical.COFFEE);

            assertThatThrownBy(store::publish)
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("opening hours");
        }

        /**
         * The shape {@code StoreService.requireStoreFor} produces for a brand-new merchant. It must
         * come out orderable: a DRAFT store is invisible to customers, which made the merchant's
         * very first product unsellable.
         */
        @Test
        void an_auto_provisioned_store_is_open_during_the_day() {
            Store store = new Store("merchant-1", "My Store", Store.Vertical.RESTAURANT);
            store.replaceHours(everyDay(LocalTime.of(9, 0), LocalTime.of(22, 0)));
            store.publish();

            assertThat(store.availabilityAt(utc(12, 0))).isEqualTo(Store.Availability.OPEN);
            assertThat(store.isOrderable(utc(12, 0))).isTrue();
        }
    }

    @Nested
    @DisplayName("split and overlapping windows")
    class Windows {

        private Store splitHours() {
            Store store = new Store("merchant-1", "Roast & Co", Store.Vertical.COFFEE);
            store.replaceHours(java.util.stream.Stream.of(DayOfWeek.values())
                    .flatMap(day -> java.util.stream.Stream.of(
                            new StoreHours(day, LocalTime.of(6, 30), LocalTime.of(11, 30)),
                            new StoreHours(day, LocalTime.of(14, 0), LocalTime.of(19, 0))))
                    .toList());
            store.publish();
            return store;
        }

        @Test
        void open_in_the_morning_window() {
            assertThat(splitHours().availabilityAt(utc(9, 0))).isEqualTo(Store.Availability.OPEN);
        }

        /** The gap is the case a single opens/closes pair per day cannot represent at all. */
        @Test
        void closed_in_the_gap_between_windows() {
            assertThat(splitHours().availabilityAt(utc(12, 30)))
                    .isEqualTo(Store.Availability.CLOSED);
        }

        @Test
        void open_again_in_the_afternoon_window() {
            assertThat(splitHours().availabilityAt(utc(15, 0))).isEqualTo(Store.Availability.OPEN);
        }

        @Test
        void closing_soon_applies_to_whichever_window_is_current() {
            // 11:00 is half an hour from the morning window closing, not from the afternoon one.
            assertThat(splitHours().availabilityAt(utc(11, 0)))
                    .isEqualTo(Store.Availability.CLOSING_SOON);
        }

        /** Two windows that touch are one stretch of open time to a customer. */
        @Test
        void overlapping_windows_resolve_to_the_latest_closing_time() {
            Store store = new Store("merchant-1", "Overlap", Store.Vertical.CONVENIENCE);
            store.replaceHours(List.of(
                    new StoreHours(DayOfWeek.WEDNESDAY, LocalTime.of(8, 0), LocalTime.of(14, 0)),
                    new StoreHours(DayOfWeek.WEDNESDAY, LocalTime.of(12, 0), LocalTime.of(20, 0))));
            store.publish();

            assertThat(store.closingTimeAt(utc(13, 0))).isEqualTo(LocalTime.of(20, 0));
            // Would read as CLOSING_SOON if the earlier window won.
            assertThat(store.availabilityAt(utc(13, 40))).isEqualTo(Store.Availability.OPEN);
        }

        @Test
        void hours_only_apply_to_their_own_weekday() {
            Store store = new Store("merchant-1", "Wednesdays only", Store.Vertical.RESTAURANT);
            store.replaceHours(List.of(
                    new StoreHours(DayOfWeek.WEDNESDAY, LocalTime.of(8, 0), LocalTime.of(23, 0))));
            store.publish();

            assertThat(store.availabilityAt(utc(12, 0))).isEqualTo(Store.Availability.OPEN);
            // Thursday, same time of day.
            assertThat(store.availabilityAt(utc(12, 0).plus(Duration.ofDays(1))))
                    .isEqualTo(Store.Availability.CLOSED);
        }

        @Test
        void a_window_must_close_after_it_opens() {
            assertThatThrownBy(() ->
                    new StoreHours(DayOfWeek.MONDAY, LocalTime.of(22, 0), LocalTime.of(2, 0)))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("midnight");
        }

        @Test
        void closing_time_is_null_when_nothing_is_open() {
            assertThat(storeOpen(LocalTime.of(8, 0), LocalTime.of(23, 0)).closingTimeAt(utc(3, 0)))
                    .isNull();
        }
    }

    @Nested
    @DisplayName("time zones")
    class Zones {

        /** The whole reason the zone is per store: 20:00 UTC is a different hour in Beirut. */
        @Test
        void hours_are_interpreted_in_the_stores_own_zone() {
            Store store = new Store("merchant-1", "Beirut Grill", Store.Vertical.RESTAURANT);
            store.updateProfile("Beirut Grill", null, null, Store.Vertical.RESTAURANT,
                    List.of(), "Asia/Beirut", null);
            store.replaceHours(everyDay(LocalTime.of(8, 0), LocalTime.of(23, 0)));
            store.publish();

            // 22:00 UTC on the Wednesday is 01:00 Thursday in Beirut (UTC+3 in August): shut.
            assertThat(store.availabilityAt(utc(22, 0))).isEqualTo(Store.Availability.CLOSED);
            // The very same instant is 22:00 for a UTC store — an hour short of closing, so open.
            assertThat(storeOpen(LocalTime.of(8, 0), LocalTime.of(23, 0)).availabilityAt(utc(22, 0)))
                    .isEqualTo(Store.Availability.OPEN);
        }

        /**
         * A bad zone is a data-entry mistake in one row. It must degrade that store's clock, not
         * throw out of a list query rendering fifty of them.
         */
        @Test
        void an_unparseable_zone_falls_back_to_utc_instead_of_throwing() {
            Store store = new Store("merchant-1", "Typo", Store.Vertical.ELECTRONICS);
            store.updateProfile("Typo", null, null, Store.Vertical.ELECTRONICS,
                    List.of(), "Not/A_Real_Zone", null);
            store.replaceHours(everyDay(LocalTime.of(8, 0), LocalTime.of(23, 0)));
            store.publish();

            assertThat(store.availabilityAt(utc(12, 0))).isEqualTo(Store.Availability.OPEN);
            assertThat(store.availabilityAt(utc(3, 0))).isEqualTo(Store.Availability.CLOSED);
        }
    }

    @Nested
    @DisplayName("slugs")
    class Slugs {

        @Test
        void punctuation_and_spacing_collapse_to_hyphens() {
            assertThat(Store.slugify("Nonna's Pizzeria & Grill")).isEqualTo("nonna-s-pizzeria-grill");
        }

        @Test
        void leading_and_trailing_separators_are_trimmed() {
            assertThat(Store.slugify("  !! Bloom & Wrap !!  ")).isEqualTo("bloom-wrap");
        }

        @Test
        void a_name_with_nothing_sluggable_still_produces_a_key() {
            assertThat(Store.slugify("!!!")).isEqualTo("store");
        }

        /** Two shops may legitimately share a name, so the id fragment is what keeps slugs unique. */
        @Test
        void two_stores_with_the_same_name_get_different_slugs() {
            Store first = new Store("m1", "Corner Shop", Store.Vertical.CONVENIENCE);
            Store second = new Store("m2", "Corner Shop", Store.Vertical.CONVENIENCE);

            assertThat(first.getSlug()).startsWith("corner-shop-");
            assertThat(second.getSlug()).startsWith("corner-shop-");
            assertThat(first.getSlug()).isNotEqualTo(second.getSlug());
        }

        /** A rename must not break a link somebody has already shared. */
        @Test
        void renaming_a_store_does_not_change_its_slug() {
            Store store = new Store("m1", "Old Name", Store.Vertical.RESTAURANT);
            String original = store.getSlug();

            store.updateProfile("Completely New Name", null, null, Store.Vertical.RESTAURANT,
                    List.of(), null, null);

            assertThat(store.getSlug()).isEqualTo(original);
        }
    }
}
