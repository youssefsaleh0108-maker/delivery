package com.delivery.product.service;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import com.delivery.product.api.dto.StoreDtos.HoursRequest;
import com.delivery.product.api.dto.StoreDtos.StoreRequest;
import com.delivery.product.domain.TestPin;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreFavoriteRepository;
import com.delivery.product.domain.StoreOffer;
import com.delivery.product.domain.StoreOfferRepository;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.StoreService.OfferNotFoundException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * What a merchant can do to their own shop, and what has to be refused rather than absorbed.
 *
 * <p>The three rules here failed in the same way: the service accepted something it could not act
 * on, and the caller was told nothing was wrong. A weekday that is not a day arrived as an
 * "Internal error"; withdrawing an offer that was not there answered 204; a coordinate that cannot
 * exist was answered "yes, we deliver". None of them is visible from the calling side.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("running a shop")
class StoreAdministrationTest {

    private static final String MERCHANT = "merchant-sub";

    @Mock
    private StoreRepository stores;
    @Mock
    private StoreOfferRepository offers;
    @Mock
    private StoreFavoriteRepository favorites;
    @Mock
    private ProductRepository products;
    @Mock
    private CategoryRepository categories;

    private StoreService service;
    private Store store;

    @BeforeEach
    void setUp() {
        service = new StoreService(stores, offers, favorites, products, categories,
                new ServiceCategories(new org.springframework.mock.env.MockEnvironment()),
                org.mockito.Mockito.mock(OnboardingApplicationClient.class),
                Clock.fixed(Instant.parse("2026-09-09T09:00:00Z"), ZoneOffset.UTC),
                Duration.ofHours(4), "Asia/Beirut");

        store = new Store(MERCHANT, "Beirut Grill", Store.Vertical.RESTAURANT);
        when(stores.findByIdAndMerchantId(store.getId(), MERCHANT)).thenReturn(Optional.of(store));
    }

    @Nested
    @DisplayName("setting the week's opening hours")
    class Hours {

        private static HoursRequest on(int dayOfWeek) {
            return new HoursRequest(dayOfWeek, LocalTime.of(9, 0), LocalTime.of(17, 0));
        }

        @Test
        void the_seven_real_days_are_accepted() {
            List<HoursRequest> week = List.of(on(1), on(2), on(3), on(4), on(5), on(6), on(7));

            assertThat(service.replaceHours(store.getId(), MERCHANT, week)
                    .store().getHours()).hasSize(7);
        }

        /**
         * Day 0 is what a client written against a zero-based calendar sends, and day 8 what one
         * counting Sunday first sends. Both used to reach {@code DayOfWeek.of} and come back as a
         * 500 — our fault, apparently, for their typo.
         */
        @Test
        void a_day_below_monday_is_refused_with_something_to_act_on() {
            assertThatThrownBy(() ->
                    service.replaceHours(store.getId(), MERCHANT, List.of(on(0))))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("Monday")
                    .hasMessageContaining("Sunday");
        }

        @Test
        void a_day_above_sunday_is_refused_the_same_way() {
            assertThatThrownBy(() ->
                    service.replaceHours(store.getId(), MERCHANT, List.of(on(8))))
                    .isInstanceOf(CatalogRuleViolationException.class);
        }

        /** Nothing is half-applied: a bad day in the list leaves the old week standing. */
        @Test
        void one_bad_day_does_not_replace_the_week() {
            service.replaceHours(store.getId(), MERCHANT, List.of(on(1), on(2)));

            assertThatThrownBy(() -> service.replaceHours(
                    store.getId(), MERCHANT, List.of(on(3), on(9))))
                    .isInstanceOf(CatalogRuleViolationException.class);

            assertThat(store.getHours()).hasSize(2);
        }

        /** The message never names the enum or the exception the lookup would have thrown. */
        @Test
        void the_refusal_reads_as_a_sentence_and_not_as_a_stack_trace() {
            assertThatThrownBy(() ->
                    service.replaceHours(store.getId(), MERCHANT, List.of(on(0))))
                    .hasMessageNotContainingAny("DayOfWeek", "DateTimeException", "java.time");
        }
    }

    @Nested
    @DisplayName("saving the profile form")
    class Profile {

        private StoreRequest profile(String neighborhood) {
            return new StoreRequest("Beirut Grill", Store.Vertical.RESTAURANT, "Grills since 1985",
                    null, List.of("grill"), null, "Hamra Street", neighborhood, null);
        }

        /**
         * The regression. Every client that saved this form before it had a district field sent no
         * district, and the service wrote that absence over the stored one — so fixing a typo in the
         * tagline silently took the shop out of its neighbourhood, and the district list was empty
         * in practice.
         */
        @Test
        void a_save_that_does_not_mention_the_neighbourhood_keeps_it() {
            store.setNeighborhood("Mar Mikhael");

            service.update(store.getId(), MERCHANT, profile(null));

            assertThat(store.getNeighborhood()).isEqualTo("Mar Mikhael");
            assertThat(store.getTagline()).isEqualTo("Grills since 1985");
        }

        @Test
        void a_save_that_names_one_sets_it_trimmed() {
            service.update(store.getId(), MERCHANT, profile("  Hamra "));

            // Trimmed, because the district list is the distinct values of this column and every
            // filter on it is exact: " Hamra" would be a second Hamra.
            assertThat(store.getNeighborhood()).isEqualTo("Hamra");
        }

        /** Only a client that knows the field exists can clear it — by saying so. */
        @Test
        void an_empty_one_clears_it() {
            store.setNeighborhood("Mar Mikhael");

            service.update(store.getId(), MERCHANT, profile(""));
            assertThat(store.getNeighborhood()).isNull();

            store.setNeighborhood("Mar Mikhael");
            service.update(store.getId(), MERCHANT, profile("   "));
            assertThat(store.getNeighborhood()).isNull();
        }

        /** Another merchant's save is refused before anything on the shop is touched. */
        @Test
        void another_merchants_save_is_refused_and_changes_nothing() {
            store.setNeighborhood("Mar Mikhael");

            assertThatThrownBy(() -> service.update(store.getId(), "someone-else", profile("Hamra")))
                    .isInstanceOf(StoreService.StoreNotFoundException.class);

            assertThat(store.getNeighborhood()).isEqualTo("Mar Mikhael");
        }

        /** The trust badge is not on this form at all, so no profile save can grant or drop it. */
        @Test
        void a_profile_save_neither_grants_nor_withdraws_the_trust_badge() {
            store.setVerifiedLocal(true);

            service.update(store.getId(), MERCHANT, profile("Hamra"));

            assertThat(store.isVerifiedLocal()).isTrue();
        }
    }

    @Nested
    @DisplayName("the trust badge")
    class TrustBadge {

        private static final String BACKOFFICE = "backoffice-sub";

        /**
         * No ownership rule — this is the one write on a shop that is never the merchant's, and who
         * may make it is the controller's role check (pinned in StoreVerifiedLocalAccessTest).
         */
        @Test
        void backoffice_grants_and_withdraws_it_on_a_shop_it_does_not_own() {
            when(stores.findById(store.getId())).thenReturn(Optional.of(store));

            assertThat(service.setVerifiedLocal(store.getId(), BACKOFFICE, true)
                    .store().isVerifiedLocal()).isTrue();
            assertThat(service.setVerifiedLocal(store.getId(), BACKOFFICE, false)
                    .store().isVerifiedLocal()).isFalse();
        }

        /**
         * A provider's "Verified" badge is this flag too (owner default 17), so no vertical is refused, a
         * service shop included.
         */
        @Test
        void backoffice_grants_and_withdraws_it_on_a_service_shop() {
            Store press = new Store(MERCHANT, "Al Fakhry Press", Store.Vertical.SERVICES,
                    Store.ServiceCategory.PRINTING);
            when(stores.findById(press.getId())).thenReturn(Optional.of(press));

            assertThat(service.setVerifiedLocal(press.getId(), BACKOFFICE, true)
                    .store().isVerifiedLocal()).isTrue();
            assertThat(press.isVerifiedLocal()).isTrue();
            assertThat(service.setVerifiedLocal(press.getId(), BACKOFFICE, false)
                    .store().isVerifiedLocal()).isFalse();
        }

        @Test
        void an_id_that_names_no_shop_is_not_found() {
            UUID nothing = UUID.randomUUID();
            when(stores.findById(nothing)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.setVerifiedLocal(nothing, BACKOFFICE, true))
                    .isInstanceOf(StoreService.StoreNotFoundException.class);
        }
    }

    @Nested
    @DisplayName("what is stamped with the service's clock")
    class Stamps {

        private static final Instant CLOCK = Instant.parse("2026-09-09T09:00:00Z");

        /**
         * "New on YouDrop" counts from the listing, not from the draft — and a shop suspended and
         * listed again keeps the day it first joined rather than turning new again.
         */
        @Test
        void publishing_stamps_the_first_listing_and_a_relisting_keeps_it() {
            service.replaceHours(store.getId(), MERCHANT, java.util.stream.IntStream.rangeClosed(1, 7)
                    .mapToObj(day -> new HoursRequest(day, LocalTime.of(9, 0), LocalTime.of(17, 0)))
                    .toList());

            TestPin.pinned(store);
            service.publish(store.getId(), MERCHANT);
            assertThat(store.getPublishedAt()).isEqualTo(CLOCK);

            store.suspend();
            store.publish(CLOCK.plus(Duration.ofDays(40)));
            assertThat(store.getPublishedAt()).isEqualTo(CLOCK);
        }

        /** How fresh the power badge is, and whether it still counts as now, are measured from this. */
        @Test
        void a_power_declaration_is_stamped_when_it_is_made() {
            service.declarePower(store.getId(), MERCHANT, Store.PowerStatus.GENERATOR, "Ovens hot");

            assertThat(store.getPowerUpdatedAt()).isEqualTo(CLOCK);
        }
    }

    @Nested
    @DisplayName("withdrawing an offer")
    class Offers {

        private StoreOffer offerOf(UUID storeId) {
            StoreOffer offer = new StoreOffer(storeId, StoreOffer.Kind.PERCENT_OFF, "20% off",
                    null, BigDecimal.valueOf(20), null);
            when(offers.findById(offer.getId())).thenReturn(Optional.of(offer));
            return offer;
        }

        @Test
        void takes_down_the_shops_own_offer() {
            StoreOffer offer = offerOf(store.getId());

            service.withdrawOffer(store.getId(), offer.getId(), MERCHANT);

            assertThat(offer.isActive()).isFalse();
        }

        /**
         * The silent miss. {@code ifPresent} meant a mistyped id was answered 204, so the merchant
         * believed the promotion was gone while it went on discounting every basket.
         */
        @Test
        void an_id_that_names_nothing_is_refused_rather_than_answered() {
            UUID nothing = UUID.randomUUID();
            when(offers.findById(nothing)).thenReturn(Optional.empty());

            assertThatThrownBy(() ->
                    service.withdrawOffer(store.getId(), nothing, MERCHANT))
                    .isInstanceOf(OfferNotFoundException.class);
        }

        /** Another shop's offer is not this shop's to withdraw, and is left running. */
        @Test
        void another_shops_offer_is_refused_and_left_alone() {
            StoreOffer theirs = offerOf(UUID.randomUUID());

            assertThatThrownBy(() ->
                    service.withdrawOffer(store.getId(), theirs.getId(), MERCHANT))
                    .isInstanceOf(OfferNotFoundException.class);

            assertThat(theirs.isActive()).isTrue();
        }
    }

    @Nested
    @DisplayName("asking whether a shop delivers to a point")
    class CanDeliver {

        @BeforeEach
        void shopDeliversEverywhere() {
            when(stores.deliversTo(any(UUID.class), anyDouble(), anyDouble())).thenReturn(null);
        }

        /** No circle drawn means the platform's zones decide, which this endpoint reads as yes. */
        @Test
        void a_real_point_is_answered() {
            assertThat(service.deliversTo(store.getId(),
                    new BigDecimal("33.8977"), new BigDecimal("35.4829"))).isTrue();
        }

        /**
         * The dropped form field. (0, 0) used to be answered "yes, we deliver" — about a point in
         * the Gulf of Guinea — and checkout promised a delivery on the strength of it.
         */
        @Test
        void null_island_is_refused_rather_than_answered() {
            assertThatThrownBy(() ->
                    service.deliversTo(store.getId(), BigDecimal.ZERO, BigDecimal.ZERO))
                    .isInstanceOf(GeoPoint.InvalidCoordinateException.class);

            verify(stores, never()).deliversTo(any(UUID.class), anyDouble(), anyDouble());
        }

        @Test
        void a_latitude_that_cannot_exist_is_refused() {
            assertThatThrownBy(() -> service.deliversTo(store.getId(),
                    new BigDecimal("999"), new BigDecimal("35.4829")))
                    .isInstanceOf(GeoPoint.InvalidCoordinateException.class);
        }

        @Test
        void a_longitude_that_cannot_exist_is_refused() {
            assertThatThrownBy(() -> service.deliversTo(store.getId(),
                    new BigDecimal("33.8977"), new BigDecimal("-1000")))
                    .isInstanceOf(GeoPoint.InvalidCoordinateException.class);
        }

        /** Half a pin is not a pin here either — the same rule /nearby applies. */
        @Test
        void half_a_coordinate_is_refused() {
            assertThatThrownBy(() ->
                    service.deliversTo(store.getId(), new BigDecimal("33.8977"), null))
                    .isInstanceOf(GeoPoint.InvalidCoordinateException.class);
        }

        @Test
        void the_edges_of_the_ranges_are_still_places() {
            assertThatCode(() -> service.deliversTo(store.getId(),
                    new BigDecimal("-90"), new BigDecimal("180")))
                    .doesNotThrowAnyException();
        }
    }
}
