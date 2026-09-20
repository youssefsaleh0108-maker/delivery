package com.delivery.product.domain;

import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalTime;
import java.util.List;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * What a shop must have before it may be listed, and what happens to the ones already listed
 * without it.
 *
 * <p>Written after finding twelve ACTIVE shops on dev, three of them from real sign-ups through the
 * public site, with no coordinates at all. A shop in that state is listed and unreachable by every
 * feature that asks where it is: it has no distance, so "shops near you" cannot rank it; no centre,
 * so it has no delivery circle and its radius cannot be enforced; and nothing anywhere says why.
 * Nothing forced a pin, because the only way to set one was a separate endpoint
 * ({@code PUT /api/stores/{id}/location}) that a merchant had to go and find.
 *
 * <p>The rule guards the TRANSITION and nothing else. That distinction is the whole design: shops
 * that went live before it existed keep trading, because taking real traders off the storefront to
 * fix a data problem they never caused would be the worse bug — and it is what the back-office pin
 * and the dev scripts are for instead.
 */
@DisplayName("what a shop needs before it can be listed")
class StoreListingRulesTest {

    private static final Instant NOON = Instant.parse("2026-09-20T09:00:00Z");

    private static Store shop() {
        return new Store("merchant-1", "Abu Hassan Mini Market", Store.Vertical.GROCERY);
    }

    private static List<StoreHours> everyDay() {
        return java.util.Arrays.stream(DayOfWeek.values())
                .map(day -> new StoreHours(day, LocalTime.of(8, 0), LocalTime.of(23, 0)))
                .toList();
    }

    @Nested
    @DisplayName("the missing pin")
    class MissingPin {

        @Test
        @DisplayName("publishing a shop with hours but no pin is refused, with the pin named")
        void no_pin_is_refused() {
            Store store = shop();
            store.replaceHours(everyDay());

            assertThatThrownBy(() -> store.publish(NOON))
                    .isInstanceOf(Store.NotListableException.class)
                    .hasMessageContaining("map");

            assertThat(store.getStatus()).isEqualTo(Store.Status.DRAFT);
        }

        /**
         * The code, not the sentence, is what the merchant app branches on to decide whether to open
         * the map picker or the week's hours. Matching English prose to choose between them is not
         * something that survives translation.
         */
        @Test
        @DisplayName("carries STORE_PIN_REQUIRED for the client to branch on")
        void the_refusal_is_coded() {
            Store store = shop();
            store.replaceHours(everyDay());

            assertThatThrownBy(() -> store.publish(NOON))
                    .isInstanceOf(Store.NotListableException.class)
                    .extracting(e -> ((Store.NotListableException) e).getCode())
                    .isEqualTo("STORE_PIN_REQUIRED");
        }

        @Test
        @DisplayName("with a pin it lists, and the pin is the one that was dropped")
        void a_pinned_shop_lists() {
            Store store = shop();
            store.replaceHours(everyDay());
            store.pinAt(TestPin.BEIRUT);

            store.publish(NOON);

            assertThat(store.getStatus()).isEqualTo(Store.Status.ACTIVE);
            assertThat(store.getPublishedAt()).isEqualTo(NOON);
            assertThat(store.location()).isEqualTo(TestPin.BEIRUT);
        }

        /**
         * Hours first. A shop with neither is being set up rather than corrected, and one problem a
         * merchant can act on beats a list of two.
         */
        @Test
        @DisplayName("a shop with neither is told about its hours first")
        void hours_are_named_before_the_pin() {
            Store store = shop();

            assertThat(store.whyNotListable()).isEqualTo(Store.NotListable.NO_HOURS);
            assertThatThrownBy(() -> store.publish(NOON))
                    .isInstanceOf(Store.NotListableException.class)
                    .extracting(e -> ((Store.NotListableException) e).getCode())
                    .isEqualTo("STORE_HOURS_REQUIRED");
        }

        /**
         * The Publish button asks the same question the refusal answers, so it can say what is
         * missing before it is pressed rather than turning a press into an error. Two computations
         * of the same rule would eventually disagree.
         */
        @Test
        @DisplayName("the question a button asks and the rule a publish enforces are one method")
        void the_button_and_the_rule_agree() {
            Store store = shop();
            assertThat(store.isListable()).isFalse();
            assertThat(store.whyNotListable()).isEqualTo(Store.NotListable.NO_HOURS);

            store.replaceHours(everyDay());
            assertThat(store.isListable()).isFalse();
            assertThat(store.whyNotListable()).isEqualTo(Store.NotListable.NO_PIN);

            store.pinAt(TestPin.BEIRUT);
            assertThat(store.isListable()).isTrue();
            assertThat(store.whyNotListable()).isNull();
        }

        /** Every refusal a client may see carries a code it can branch on. */
        @Test
        @DisplayName("every reason has a code and a sentence")
        void every_reason_is_actionable() {
            for (Store.NotListable reason : Store.NotListable.values()) {
                assertThat(reason.code()).isNotBlank().doesNotContain(" ");
                assertThat(reason.message()).isNotBlank().hasSizeGreaterThan(20);
            }
        }
    }

    @Nested
    @DisplayName("a shop that is already listed")
    class AlreadyListed {

        /**
         * The twelve shops on dev. They stay exactly as they are — pinless, trading, findable by
         * name and by category, just not by distance.
         */
        @Test
        @DisplayName("keeps trading after losing its pin: only the transition is guarded")
        void unpinning_a_live_shop_does_not_unlist_it() {
            Store store = shop();
            store.replaceHours(everyDay());
            store.pinAt(TestPin.BEIRUT);
            store.publish(NOON);

            store.clearPin();

            assertThat(store.getStatus()).isEqualTo(Store.Status.ACTIVE);
            assertThat(store.availabilityAt(NOON)).isEqualTo(Store.Availability.OPEN);
            assertThat(store.location()).isNull();
        }

        /**
         * But it cannot be re-listed without one. A shop that was suspended has had a decision made
         * about it, and putting it back on the storefront is a fresh listing.
         */
        @Test
        @DisplayName("cannot be re-listed after a suspension without a pin")
        void relisting_needs_the_pin_again() {
            Store store = shop();
            store.replaceHours(everyDay());
            store.pinAt(TestPin.BEIRUT);
            store.publish(NOON);
            store.suspend();
            store.clearPin();

            assertThatThrownBy(() -> store.publish(NOON))
                    .isInstanceOf(Store.NotListableException.class)
                    .extracting(e -> ((Store.NotListableException) e).getCode())
                    .isEqualTo("STORE_PIN_REQUIRED");

            assertThat(store.getStatus()).isEqualTo(Store.Status.SUSPENDED);
        }
    }

    @Nested
    @DisplayName("the shop's calendar")
    class Calendar {

        @Test
        @DisplayName("a blank zone leaves the shop's own alone, as the profile form does")
        void a_blank_zone_is_ignored() {
            Store store = shop();
            store.useTimezone("Asia/Beirut");

            store.useTimezone(null);
            store.useTimezone("   ");

            assertThat(store.getTimezone()).isEqualTo("Asia/Beirut");
        }

        /**
         * The bug this whole change is about, stated as a test: 20:00 UTC is 23:00 in Beirut, so the
         * same shop with the same 08:00-23:00 week is shut in one calendar and open in the other.
         */
        @Test
        @DisplayName("the same hours in UTC and in Beirut are not the same shop")
        void the_zone_changes_when_a_shop_is_open() {
            Store beirut = shop();
            beirut.useTimezone("Asia/Beirut");
            beirut.replaceHours(everyDay());
            beirut.pinAt(TestPin.BEIRUT);
            beirut.publish(NOON);

            Store utc = shop();
            utc.replaceHours(everyDay());
            utc.pinAt(TestPin.BEIRUT);
            utc.publish(NOON);
            assertThat(utc.getTimezone()).isEqualTo("UTC");

            // 21:00 UTC is midnight in Beirut (UTC+3 in September): shut there, still trading here.
            Instant lateEvening = Instant.parse("2026-09-20T21:00:00Z");
            assertThat(beirut.availabilityAt(lateEvening)).isEqualTo(Store.Availability.CLOSED);
            assertThat(utc.availabilityAt(lateEvening)).isEqualTo(Store.Availability.OPEN);

            // And the mirror image: 06:00 UTC is 09:00 Beirut. Open there, an hour before opening here.
            Instant earlyMorning = Instant.parse("2026-09-20T06:00:00Z");
            assertThat(beirut.availabilityAt(earlyMorning)).isEqualTo(Store.Availability.OPEN);
            assertThat(utc.availabilityAt(earlyMorning)).isEqualTo(Store.Availability.CLOSED);
        }
    }
}
