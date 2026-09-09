package com.delivery.product.service;

import java.math.BigDecimal;
import java.time.Clock;
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
                Clock.fixed(Instant.parse("2026-09-09T09:00:00Z"), ZoneOffset.UTC));

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
