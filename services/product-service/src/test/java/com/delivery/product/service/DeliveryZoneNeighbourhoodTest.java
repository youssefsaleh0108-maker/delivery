package com.delivery.product.service;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import com.delivery.product.domain.DeliveryZone;
import com.delivery.product.domain.DeliveryZoneRepository;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreDeliveryZone;
import com.delivery.product.domain.StoreDeliveryZoneRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

/**
 * Where an area sits, and which areas lie around a shop — the two things V30 added for the merchant
 * Demand Radar.
 *
 * <p>"Around" matters more than it looks. Order Manager counts demand in exactly the areas this
 * answers and nowhere else, so this is the rule that keeps a merchant looking at their own
 * neighbourhood rather than at the platform. Two of its inputs are the merchant's to set — the areas
 * the shop prices and the width of its delivery circle — so neither may widen it past the cap. The
 * coordinates are real ones, so the distances the assertions depend on can be checked against a map:
 * Badaro, Mar Mikhael and Ghobeiry are each four to five kilometres from Hamra, Jounieh about sixteen.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("areas on a map")
class DeliveryZoneNeighbourhoodTest {

    private static final GeoPoint HAMRA_CENTRE = GeoPoint.of(33.8959, 35.4787);
    private static final GeoPoint MAR_MIKHAEL_CENTRE = GeoPoint.of(33.8981, 35.5244);
    private static final GeoPoint BADARO_CENTRE = GeoPoint.of(33.8745, 35.5147);
    private static final GeoPoint GHOBEIRY_CENTRE = GeoPoint.of(33.8600, 35.5050);
    private static final GeoPoint JOUNIEH_CENTRE = GeoPoint.of(33.9808, 35.6178);

    /** The cap the platform runs with when nothing configures another. */
    private static final int CAP = 5_000;

    @Mock
    private DeliveryZoneRepository zones;
    @Mock
    private StoreDeliveryZoneRepository storeZones;

    private DeliveryZoneService service;
    private Store shop;

    private DeliveryZone hamra;
    private DeliveryZone marMikhael;
    private DeliveryZone badaro;
    private DeliveryZone jounieh;

    @BeforeEach
    void setUp() {
        service = new DeliveryZoneService(zones, storeZones, CAP);
        shop = new Store("merchant-1", "Hamra Sushi", Store.Vertical.RESTAURANT);

        hamra = placed("Hamra", "Beirut", 10, HAMRA_CENTRE);
        marMikhael = placed("Mar Mikhael", "Beirut", 20, MAR_MIKHAEL_CENTRE);
        badaro = placed("Badaro", "Beirut", 30, BADARO_CENTRE);
        jounieh = placed("Jounieh", "Keserwan", 40, JOUNIEH_CENTRE);

        when(zones.findByActiveTrueOrderBySortOrderAscNameAsc())
                .thenReturn(List.of(hamra, marMikhael, badaro, jounieh));
        when(storeZones.findByStoreId(any())).thenReturn(List.of());
    }

    private static DeliveryZone placed(String name, String region, int rank, GeoPoint centre) {
        DeliveryZone zone = new DeliveryZone(name, region, rank);
        zone.placeAt(centre);
        return zone;
    }

    private void shopDeliversTo(DeliveryZone... areas) {
        when(storeZones.findByStoreId(shop.getId())).thenReturn(java.util.Arrays.stream(areas)
                .map(z -> new StoreDeliveryZone(shop.getId(), z.getId(), new BigDecimal("2.00"),
                        null, 0))
                .toList());
    }

    @Nested
    @DisplayName("an area's centre")
    class Centre {

        @BeforeEach
        void hamraCanBeEdited() {
            when(zones.findById(hamra.getId())).thenReturn(Optional.of(hamra));
            when(zones.findByNameIgnoreCase("Hamra")).thenReturn(Optional.of(hamra));
        }

        @Test
        void a_new_area_can_be_placed_as_it_is_created() {
            when(zones.existsByNameIgnoreCase("Gemmayze")).thenReturn(false);
            when(zones.save(any(DeliveryZone.class))).thenAnswer(i -> i.getArgument(0));

            DeliveryZone created = service.create("Gemmayze", "Beirut", 15,
                    GeoPoint.of(33.8950, 35.5160));

            assertThat(created.getCenterLat()).isEqualByComparingTo("33.895000");
            assertThat(created.getCenterLng()).isEqualByComparingTo("35.516000");
        }

        @Test
        void editing_an_area_without_a_word_about_its_centre_keeps_the_centre() {
            // What every client written before centres existed sends: name, region and rank alone.
            // A rename or a reorder from one of them must not take the area off every shop's map.
            service.rename(hamra.getId(), "Hamra", "Beirut", 5, null, false);

            assertThat(hamra.centre()).isEqualTo(HAMRA_CENTRE);
            assertThat(hamra.getSortOrder()).isEqualTo(5);
        }

        @Test
        void clearing_the_centre_takes_the_area_off_the_map_and_leaves_the_rest() {
            service.rename(hamra.getId(), "Hamra", "Beirut", 5, null, true);

            assertThat(hamra.centre()).isNull();
            assertThat(hamra.getCenterLat()).isNull();
            assertThat(hamra.getCenterLng()).isNull();
            assertThat(hamra.getSortOrder()).isEqualTo(5);
        }

        @Test
        void a_new_centre_moves_the_area() {
            service.rename(hamra.getId(), "Hamra", "Beirut", 10, GeoPoint.of(33.8970, 35.4800),
                    false);

            assertThat(hamra.centre()).isEqualTo(GeoPoint.of(33.8970, 35.4800));
        }

        @Test
        void half_a_centre_is_refused_rather_than_drawn_on_the_prime_meridian() {
            assertThatThrownBy(() -> GeoPoint.ofNullable(new BigDecimal("33.8959"), null))
                    .isInstanceOf(GeoPoint.InvalidCoordinateException.class);
        }
    }

    @Nested
    @DisplayName("the areas around a shop")
    class Around {

        @Test
        void a_pinned_shop_sees_the_placed_areas_within_five_kilometres() {
            shop.pinAt(HAMRA_CENTRE);

            DeliveryZoneService.Neighbourhood around = service.around(shop);

            assertThat(around.zones()).containsExactly(hamra, marMikhael, badaro);
            assertThat(around.radiusMetres())
                    .isEqualTo(DeliveryZoneService.DEFAULT_NEIGHBOURHOOD_METRES);
            assertThat(around.region()).isEqualTo("Beirut");
        }

        @Test
        void a_shop_that_draws_its_own_delivery_circle_is_held_to_it() {
            // A shop that carries a kilometre has no use for demand four kilometres away.
            shop.pinAt(HAMRA_CENTRE);
            shop.setDeliveryRadiusMetres(1_000);

            DeliveryZoneService.Neighbourhood around = service.around(shop);

            assertThat(around.zones()).containsExactly(hamra);
            assertThat(around.radiusMetres()).isEqualTo(1_000);
        }

        @Test
        void a_nearby_area_the_shop_prices_counts_even_past_its_own_circle() {
            shop.pinAt(HAMRA_CENTRE);
            shop.setDeliveryRadiusMetres(1_000);
            shopDeliversTo(badaro);

            assertThat(service.around(shop).zones()).containsExactly(hamra, badaro);
        }

        @Test
        void a_far_area_the_shop_prices_is_not_around_it() {
            // Any merchant may price any area on the platform. Were a coverage row enough, a Hamra
            // shop pricing Jounieh would put Jounieh's demand on its map — and a shop pricing every
            // area would read the whole platform.
            shop.pinAt(HAMRA_CENTRE);
            shopDeliversTo(jounieh);

            assertThat(service.around(shop).zones()).containsExactly(hamra, marMikhael, badaro);
        }

        @Test
        void a_fifty_kilometre_delivery_circle_is_held_to_the_cap() {
            shop.pinAt(HAMRA_CENTRE);
            shop.setDeliveryRadiusMetres(50_000);

            DeliveryZoneService.Neighbourhood around = service.around(shop);

            assertThat(around.zones()).containsExactly(hamra, marMikhael, badaro);
            assertThat(around.radiusMetres()).isEqualTo(CAP);
        }

        @Test
        void the_cap_is_the_platforms_setting() {
            DeliveryZoneService narrow = new DeliveryZoneService(zones, storeZones, 3_000);
            shop.pinAt(HAMRA_CENTRE);
            shopDeliversTo(badaro);

            DeliveryZoneService.Neighbourhood around = narrow.around(shop);

            assertThat(around.zones()).containsExactly(hamra);
            assertThat(around.radiusMetres()).isEqualTo(3_000);
        }

        @Test
        void a_cap_outside_sane_bounds_stops_the_service_from_starting() {
            assertThatThrownBy(() -> new DeliveryZoneService(zones, storeZones, 0))
                    .isInstanceOf(IllegalArgumentException.class);
            assertThatThrownBy(() -> new DeliveryZoneService(zones, storeZones, 50_000))
                    .isInstanceOf(IllegalArgumentException.class);
        }

        @Test
        void a_shop_with_no_pin_has_no_neighbourhood_even_where_it_delivers() {
            shopDeliversTo(badaro, jounieh);

            DeliveryZoneService.Neighbourhood around = service.around(shop);

            assertThat(around.zones()).isEmpty();
            assertThat(around.radiusMetres()).isNull();
        }

        @Test
        void an_unplaced_area_is_around_nobody_even_where_the_shop_delivers() {
            DeliveryZone verdun = new DeliveryZone("Verdun", "Beirut", 50);
            when(zones.findByActiveTrueOrderBySortOrderAscNameAsc())
                    .thenReturn(List.of(hamra, verdun));
            shop.pinAt(HAMRA_CENTRE);
            shopDeliversTo(verdun);

            assertThat(service.around(shop).zones()).containsExactly(hamra);
        }

        @Test
        void a_retired_area_is_around_nobody_even_where_a_shop_still_prices_it() {
            DeliveryZone retired = placed("Old Souk", "Beirut", 60, HAMRA_CENTRE);
            retired.retire();
            shop.pinAt(HAMRA_CENTRE);
            // The active list is what the repository hands back; the coverage row outlives the
            // area it names.
            shopDeliversTo(retired);

            assertThat(service.around(shop).zones()).doesNotContain(retired);
        }

        @Test
        void a_shop_with_no_pin_and_no_areas_has_no_neighbourhood_to_show() {
            DeliveryZoneService.Neighbourhood around = service.around(shop);

            assertThat(around.zones()).isEmpty();
            assertThat(around.region()).isNull();
            assertThat(around.radiusMetres()).isNull();
        }

        @Test
        void the_city_label_is_the_region_most_of_the_areas_share() {
            DeliveryZone ghobeiry = placed("Ghobeiry", "Mount Lebanon", 5, GHOBEIRY_CENTRE);
            when(zones.findByActiveTrueOrderBySortOrderAscNameAsc())
                    .thenReturn(List.of(ghobeiry, hamra, marMikhael, badaro, jounieh));
            shop.pinAt(HAMRA_CENTRE);

            DeliveryZoneService.Neighbourhood around = service.around(shop);

            // Ghobeiry comes first in the picker, but three of the four areas are in Beirut.
            assertThat(around.zones()).containsExactly(ghobeiry, hamra, marMikhael, badaro);
            assertThat(around.region()).isEqualTo("Beirut");
        }
    }
}
