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
 * neighbourhood rather than at the platform. The coordinates are real Beirut ones, so the distances
 * the assertions depend on can be checked against a map: Mar Mikhael and Badaro are each about four
 * kilometres from Hamra, Jounieh about sixteen.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("areas on a map")
class DeliveryZoneNeighbourhoodTest {

    private static final GeoPoint HAMRA_CENTRE = GeoPoint.of(33.8959, 35.4787);
    private static final GeoPoint MAR_MIKHAEL_CENTRE = GeoPoint.of(33.8981, 35.5244);
    private static final GeoPoint BADARO_CENTRE = GeoPoint.of(33.8745, 35.5147);
    private static final GeoPoint JOUNIEH_CENTRE = GeoPoint.of(33.9808, 35.6178);

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
        service = new DeliveryZoneService(zones, storeZones);
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
        void editing_an_area_without_a_centre_takes_it_off_the_map_and_leaves_the_rest() {
            // The back office's edit replaces the whole area. An area left unplaced is listed
            // rather than drawn; nothing about pricing reads the centre.
            when(zones.findById(hamra.getId())).thenReturn(Optional.of(hamra));
            when(zones.findByNameIgnoreCase("Hamra")).thenReturn(Optional.of(hamra));

            service.rename(hamra.getId(), "Hamra", "Beirut", 5, null);

            assertThat(hamra.centre()).isNull();
            assertThat(hamra.getCenterLat()).isNull();
            assertThat(hamra.getCenterLng()).isNull();
            assertThat(hamra.getSortOrder()).isEqualTo(5);
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
        void the_areas_a_shop_delivers_to_count_however_far_they_are() {
            shop.pinAt(HAMRA_CENTRE);
            shopDeliversTo(jounieh);

            assertThat(service.around(shop).zones()).containsExactly(hamra, marMikhael, badaro,
                    jounieh);
        }

        @Test
        void a_shop_with_no_pin_is_around_its_own_coverage_and_nothing_else() {
            shopDeliversTo(badaro);

            DeliveryZoneService.Neighbourhood around = service.around(shop);

            assertThat(around.zones()).containsExactly(badaro);
            assertThat(around.radiusMetres()).isNull();
        }

        @Test
        void an_unplaced_area_is_found_only_through_coverage() {
            DeliveryZone verdun = new DeliveryZone("Verdun", "Beirut", 50);
            when(zones.findByActiveTrueOrderBySortOrderAscNameAsc())
                    .thenReturn(List.of(hamra, verdun));
            shop.pinAt(HAMRA_CENTRE);

            assertThat(service.around(shop).zones()).containsExactly(hamra);

            shopDeliversTo(verdun);

            assertThat(service.around(shop).zones()).containsExactly(hamra, verdun);
        }

        @Test
        void a_retired_area_is_around_nobody_even_where_a_shop_still_prices_it() {
            DeliveryZone retired = placed("Old Souk", "Beirut", 60, HAMRA_CENTRE);
            retired.retire();
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
            shopDeliversTo(jounieh, hamra, marMikhael);

            assertThat(service.around(shop).region()).isEqualTo("Beirut");
        }
    }
}
