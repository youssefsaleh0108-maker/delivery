package com.delivery.product.api;

import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.product.domain.DeliveryZone;
import com.delivery.product.domain.DeliveryZoneRepository;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.StoreDeliveryZoneRepository;
import com.delivery.product.service.DeliveryZoneService;
import com.delivery.product.service.StoreService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * PUT /api/delivery-zones/{id} — what an edit does to an area's centre, from the JSON a client sends.
 *
 * <p>Through the real controller, JSON binding, validation and service, over mocked repositories,
 * because the defect this pins lived in the gap between them: a body with no centre bound to a null
 * centre, and a null centre wiped the stored one. Every client written before centres existed sends
 * exactly that body — main's portal, a cached web bundle, a back-office tab left open — so a rename
 * or a reorder from any of them silently dropped the area off every merchant's demand map.
 */
@DisplayName("editing an area's centre")
class DeliveryZoneCentreEditTest {

    private static final GeoPoint HAMRA_CENTRE = GeoPoint.of(33.8959, 35.4787);

    private DeliveryZone hamra;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        DeliveryZoneRepository zones = mock(DeliveryZoneRepository.class);
        hamra = new DeliveryZone("Hamra", "Beirut", 10);
        hamra.placeAt(HAMRA_CENTRE);
        when(zones.findById(hamra.getId())).thenReturn(Optional.of(hamra));
        when(zones.findByNameIgnoreCase(anyString())).thenReturn(Optional.of(hamra));

        DeliveryZoneController controller = new DeliveryZoneController(
                new DeliveryZoneService(zones, mock(StoreDeliveryZoneRepository.class), 5_000),
                mock(StoreService.class));
        mvc = MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new ApiExceptionHandler())
                .build();
    }

    private ResultActions edit(String body) throws Exception {
        return mvc.perform(put("/api/delivery-zones/" + hamra.getId())
                .contentType(MediaType.APPLICATION_JSON)
                .content(body));
    }

    @Test
    void a_client_that_predates_centres_reorders_the_area_and_its_centre_stays() throws Exception {
        edit("""
                {"name": "Hamra", "region": "Beirut", "sortOrder": 5}
                """).andExpect(status().isOk());

        assertThat(hamra.getSortOrder()).isEqualTo(5);
        assertThat(hamra.centre()).isEqualTo(HAMRA_CENTRE);
    }

    @Test
    void centre_fields_sent_as_null_keep_the_centre_too() throws Exception {
        edit("""
                {"name": "Hamra", "region": "Beirut", "sortOrder": 10,
                 "centerLat": null, "centerLng": null}
                """).andExpect(status().isOk());

        assertThat(hamra.centre()).isEqualTo(HAMRA_CENTRE);
    }

    @Test
    void clear_centre_takes_the_area_off_the_map() throws Exception {
        edit("""
                {"name": "Hamra", "region": "Beirut", "sortOrder": 10, "clearCentre": true}
                """).andExpect(status().isOk());

        assertThat(hamra.centre()).isNull();
        assertThat(hamra.getName()).isEqualTo("Hamra");
    }

    @Test
    void a_new_centre_moves_the_area() throws Exception {
        edit("""
                {"name": "Hamra", "region": "Beirut", "sortOrder": 10,
                 "centerLat": 33.8970, "centerLng": 35.4800, "clearCentre": false}
                """).andExpect(status().isOk());

        assertThat(hamra.centre()).isEqualTo(GeoPoint.of(33.8970, 35.4800));
    }

    @Test
    void a_centre_and_clear_centre_together_are_refused_and_nothing_changes() throws Exception {
        edit("""
                {"name": "Renamed", "region": "Beirut", "sortOrder": 1,
                 "centerLat": 33.8970, "centerLng": 35.4800, "clearCentre": true}
                """).andExpect(status().isBadRequest());

        assertThat(hamra.centre()).isEqualTo(HAMRA_CENTRE);
        assertThat(hamra.getName()).isEqualTo("Hamra");
    }
}
