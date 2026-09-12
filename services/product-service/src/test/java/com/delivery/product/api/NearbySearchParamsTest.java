package com.delivery.product.api;

import java.util.List;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PageableHandlerMethodArgumentResolver;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Store;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ReviewService;
import com.delivery.product.service.StoreImageService;
import com.delivery.product.service.StoreService;
import com.delivery.product.service.StoreService.NearbyFilters;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * What the neighbourhood browse's chips turn into on the way to the service.
 *
 * <p>The filters themselves are pinned in {@code NearbyStoreSearchTest}; this pins the binding in
 * front of them — that each chip reaches the service as the filter it names, that an absent one is
 * no filter rather than a false one, and that the day window is clamped the way the radius is.
 */
@DisplayName("the nearby search's query string")
class NearbySearchParamsTest {

    private static final String NEAR_HAMRA = "/api/stores/nearby?latitude=33.8977&longitude=35.4829";

    private StoreService storeService;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        storeService = mock(StoreService.class);
        when(storeService.nearby(any(GeoPoint.class), anyDouble(), anyInt(),
                any(NearbyFilters.class), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of()));

        mvc = MockMvcBuilders.standaloneSetup(new StoreController(storeService,
                        mock(CatalogService.class), mock(ProductImageService.class),
                        mock(StoreImageService.class), mock(ReviewService.class)))
                // What Spring Data's web support registers in the real app; a standalone setup
                // does not know how to build a Pageable without it.
                .setCustomArgumentResolvers(new PageableHandlerMethodArgumentResolver())
                .build();

        // Nearby is authenticated-only in the real chain; any signed-in caller will do here.
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject("shopper").build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private NearbyFilters filtersFor(String query) throws Exception {
        mvc.perform(get(NEAR_HAMRA + query)).andExpect(status().isOk());
        ArgumentCaptor<NearbyFilters> filters = ArgumentCaptor.forClass(NearbyFilters.class);
        verify(storeService).nearby(any(GeoPoint.class), anyDouble(), anyInt(),
                filters.capture(), any(Pageable.class));
        return filters.getValue();
    }

    /** The existing callers — the home rail — send none of these and must get the plain search. */
    @Test
    void no_chip_is_no_filter() throws Exception {
        assertThat(filtersFor("")).isEqualTo(NearbyFilters.NONE);
    }

    @Test
    void every_chip_reaches_the_service_as_the_filter_it_names() throws Exception {
        // As params rather than in the URL: get(String) treats its argument as a template and
        // would encode the space a second time.
        mvc.perform(get(NEAR_HAMRA)
                        .param("openNow", "true")
                        .param("powerStatus", "GENERATOR")
                        .param("neighborhood", "Mar Mikhael")
                        .param("newSinceDays", "30")
                        .param("verifiedLocal", "true"))
                .andExpect(status().isOk());

        ArgumentCaptor<NearbyFilters> filters = ArgumentCaptor.forClass(NearbyFilters.class);
        verify(storeService).nearby(any(GeoPoint.class), anyDouble(), anyInt(),
                filters.capture(), any(Pageable.class));
        assertThat(filters.getValue()).isEqualTo(new NearbyFilters(
                true, Store.PowerStatus.GENERATOR, "Mar Mikhael", 30, true));
    }

    @Test
    void a_day_window_past_a_year_is_clamped_to_a_year() throws Exception {
        assertThat(filtersFor("&newSinceDays=100000").newSinceDays())
                .isEqualTo(StoreController.MAX_NEW_SINCE_DAYS);
    }

    @Test
    void a_day_window_of_nothing_is_clamped_to_one_day() throws Exception {
        assertThat(filtersFor("&newSinceDays=0").newSinceDays()).isEqualTo(1);
    }

    /** Not a state the lights can be in, so not a filter the service can apply. */
    @Test
    void a_power_status_that_does_not_exist_is_refused() throws Exception {
        mvc.perform(get(NEAR_HAMRA + "&powerStatus=HAS_GENERATOR"))
                .andExpect(status().isBadRequest());

        verify(storeService, never()).nearby(any(GeoPoint.class), anyDouble(), anyInt(),
                any(NearbyFilters.class), any(Pageable.class));
    }
}
