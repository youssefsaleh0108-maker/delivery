package com.delivery.product.service;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

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
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreDeliveryZone;
import com.delivery.product.domain.StoreDeliveryZoneRepository;

/**
 * Delivery priced by area.
 *
 * <p>The property that makes this safe to ship is the fallback: a shop that has set no areas must
 * behave exactly as it did before areas existed. Everything else here is about the difference
 * between "this shop charges more to go there" and "this shop does not go there", which is the
 * distinction the whole feature exists to express.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("delivery zones")
class DeliveryZoneServiceTest {

    private static final UUID HAMRA = UUID.randomUUID();
    private static final UUID FAR_AWAY = UUID.randomUUID();

    @Mock
    private DeliveryZoneRepository zones;
    @Mock
    private StoreDeliveryZoneRepository storeZones;

    private DeliveryZoneService service;
    private Store store;

    @BeforeEach
    void setUp() {
        service = new DeliveryZoneService(zones, storeZones);
        store = new Store("merchant-1", "Smoke Test Kitchen", Store.Vertical.RESTAURANT);
        store.updateCommercials(new BigDecimal("3.00"), new BigDecimal("10.00"), 20, 40);
    }

    private void shopPricesByArea(boolean does) {
        when(storeZones.existsByStoreId(any())).thenReturn(does);
    }

    private void serves(UUID zoneId, String fee, String minOrder, int etaExtra) {
        when(storeZones.findByStoreIdAndZoneId(any(), org.mockito.ArgumentMatchers.eq(zoneId)))
                .thenReturn(Optional.of(new StoreDeliveryZone(store.getId(), zoneId,
                        new BigDecimal(fee),
                        minOrder == null ? null : new BigDecimal(minOrder),
                        etaExtra)));
    }

    @Nested
    @DisplayName("a shop that has not set any areas")
    class NoAreas {

        @Test
        void keeps_its_flat_fee_and_serves_everywhere() {
            // The whole reason this can be turned on without a migration: nothing changes for a
            // shop that has not opted in.
            shopPricesByArea(false);

            DeliveryZoneService.Terms terms = service.termsFor(store, HAMRA);

            assertThat(terms.served()).isTrue();
            assertThat(terms.deliveryFee()).isEqualByComparingTo("3.00");
            assertThat(terms.minOrder()).isEqualByComparingTo("10.00");
            assertThat(terms.etaMinMinutes()).isEqualTo(20);
        }

        @Test
        void and_serves_an_order_with_no_area_at_all() {
            shopPricesByArea(false);

            assertThat(service.termsFor(store, null).served()).isTrue();
        }
    }

    @Nested
    @DisplayName("a shop that prices by area")
    class ByArea {

        @Test
        void charges_what_it_set_for_that_area() {
            shopPricesByArea(true);
            serves(HAMRA, "5.50", null, 0);

            DeliveryZoneService.Terms terms = service.termsFor(store, HAMRA);

            assertThat(terms.served()).isTrue();
            assertThat(terms.deliveryFee()).isEqualByComparingTo("5.50");
        }

        @Test
        void refuses_an_area_it_did_not_set() {
            // "We don't go that far" — the commonest delivery rule in this market, and one the
            // platform could not express at all before.
            shopPricesByArea(true);
            when(storeZones.findByStoreIdAndZoneId(any(), org.mockito.ArgumentMatchers.eq(FAR_AWAY)))
                    .thenReturn(Optional.empty());

            assertThat(service.termsFor(store, FAR_AWAY).served()).isFalse();
        }

        @Test
        void falls_back_to_its_own_minimum_when_the_area_names_none() {
            // Null means "use the shop's minimum", not "no minimum" — otherwise leaving the field
            // blank would silently drop the floor to zero.
            shopPricesByArea(true);
            serves(HAMRA, "5.50", null, 0);

            assertThat(service.termsFor(store, HAMRA).minOrder()).isEqualByComparingTo("10.00");
        }

        @Test
        void uses_the_areas_own_minimum_when_it_sets_one() {
            shopPricesByArea(true);
            serves(HAMRA, "5.50", "25.00", 0);

            assertThat(service.termsFor(store, HAMRA).minOrder()).isEqualByComparingTo("25.00");
        }

        @Test
        void quotes_a_longer_eta_for_a_further_area() {
            // Quoting the same window everywhere is how an ETA stops being believed.
            shopPricesByArea(true);
            serves(FAR_AWAY, "8.00", null, 15);

            DeliveryZoneService.Terms terms = service.termsFor(store, FAR_AWAY);

            assertThat(terms.etaMinMinutes()).isEqualTo(35);
            assertThat(terms.etaMaxMinutes()).isEqualTo(55);
        }

        @Test
        void still_serves_an_order_that_names_no_area() {
            // A client that predates areas, or an order placed before the customer picked one.
            // Failing here would break every existing app the moment a merchant sets one area.
            shopPricesByArea(true);

            assertThat(service.termsFor(store, null).served()).isTrue();
            assertThat(service.termsFor(store, null).deliveryFee()).isEqualByComparingTo("3.00");
        }
    }

    @Nested
    @DisplayName("the area register")
    class Register {

        @Test
        void refuses_two_areas_with_the_same_name() {
            // Two shops calling the same neighbourhood by different names makes "do you deliver to
            // me" unanswerable; two areas with the same name makes it ambiguous.
            when(zones.existsByNameIgnoreCase("Hamra")).thenReturn(true);

            org.assertj.core.api.Assertions
                    .assertThatThrownBy(() -> service.create("Hamra", "Beirut", 10))
                    .isInstanceOf(DeliveryZoneService.ZoneConflictException.class);
        }

        @Test
        void retiring_an_area_keeps_it_for_the_addresses_that_name_it() {
            DeliveryZone hamra = new DeliveryZone("Hamra", "Beirut", 10);
            when(zones.findById(any())).thenReturn(Optional.of(hamra));
            when(storeZones.findByZoneId(any())).thenReturn(List.of());

            service.retire(hamra.getId());

            // Retired, not deleted: a saved address that names it must keep resolving.
            assertThat(hamra.isActive()).isFalse();
        }

        @Test
        void a_renamed_area_may_keep_its_own_name() {
            DeliveryZone hamra = new DeliveryZone("Hamra", "Beirut", 10);
            when(zones.findById(any())).thenReturn(Optional.of(hamra));
            when(zones.findByNameIgnoreCase("Hamra")).thenReturn(Optional.of(hamra));

            service.rename(hamra.getId(), "Hamra", "Beirut", 5);

            assertThat(hamra.getSortOrder()).isEqualTo(5);
        }
    }
}
