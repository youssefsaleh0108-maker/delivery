package com.delivery.product.api;

import java.lang.reflect.RecordComponent;
import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authorization.method.AuthorizationManagerBeforeMethodInterceptor;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import com.delivery.product.api.dto.DemandDtos.UnmetDemandResponse;
import com.delivery.product.api.dto.DemandDtos.UnmetTermResponse;
import com.delivery.product.domain.DeliveryZone;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.SearchDemandWeek;
import com.delivery.product.domain.SearchDemandWeekRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.domain.TestPin;
import com.delivery.product.service.DeliveryZoneService;
import com.delivery.product.service.DemandWeeks;
import com.delivery.product.service.MerchantUnmetDemand;
import com.delivery.product.service.StoreService;
import com.delivery.product.service.UnmetDemand;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * {@code GET /api/products/demand/unmet/{storeId}} — who may read what a neighbourhood could not
 * find, and what they are told.
 *
 * <p>Two things are being defended. <strong>A merchant sees only their own area</strong>: the area
 * ids are taken from the shop's own pin and never from the request, another merchant's shop is a 404
 * indistinguishable from a shop that does not exist, and a shop that is not live is refused for both
 * roles — a draft costs nothing to create, so serving one would let anybody pin a test shop anywhere
 * and read that street. <strong>And nothing about who searched ever reaches the response</strong>,
 * which is checked here by walking the response's own record components rather than by reading the
 * class: a field added later that carried a customer, a coordinate or a timestamp would fail this.
 *
 * <p>The controller is wrapped in Spring Security's real {@code @PreAuthorize} interceptor, as
 * {@code DeliveryZoneAroundAccessTest} wraps the neighbourhood read this is built on.
 */
@DisplayName("reading what the neighbourhood could not find")
class UnmetDemandAccessTest {

    private static final String OWNER = "merchant-owner-sub";
    private static final Instant NOW = Instant.parse("2026-09-16T10:30:00Z");

    private StoreService stores;
    private DeliveryZoneService zones;
    private SearchDemandWeekRepository weeks;
    private UnmetDemandController controller;
    private Store shop;
    private DeliveryZone hamra;
    private DeliveryZone achrafieh;
    private final DemandWeeks calendar = new DemandWeeks(ZoneId.of("Asia/Beirut"));

    @BeforeEach
    void setUp() {
        stores = mock(StoreService.class);
        zones = mock(DeliveryZoneService.class);
        weeks = mock(SearchDemandWeekRepository.class);
        StoreRepository storeRepository = mock(StoreRepository.class);
        UnmetDemand unmet = mock(UnmetDemand.class);
        when(unmet.farMetres()).thenReturn(2_000);

        shop = liveShop(OWNER);
        hamra = placed("Hamra", 33.8959d, 35.4787d);
        achrafieh = placed("Achrafieh", 33.8865d, 35.5165d);

        when(stores.read(eq(shop.getId().toString()), any())).thenReturn(shop);
        when(zones.around(shop))
                .thenReturn(new DeliveryZoneService.Neighbourhood("Beirut", 5_000, List.of(hamra)));
        when(storeRepository.findByMerchantIdOrderByCreatedAtDesc(OWNER)).thenReturn(List.of(shop));
        when(weeks.alreadySold(anyCollection(), anyCollection())).thenReturn(List.of());

        MerchantUnmetDemand merchant = new MerchantUnmetDemand(weeks, zones, storeRepository,
                calendar, unmet, Clock.fixed(NOW, ZoneOffset.UTC));
        ProxyFactory secured = new ProxyFactory(new UnmetDemandController(merchant, stores));
        secured.setProxyTargetClass(true);
        secured.addAdvisor(AuthorizationManagerBeforeMethodInterceptor.preAuthorize());
        controller = (UnmetDemandController) secured.getProxy();
    }

    @AfterEach
    void signOut() {
        SecurityContextHolder.clearContext();
    }

    // ------------------------------------------------------------------------------------ who

    @Test
    @DisplayName("the owner reads their own shop")
    void the_owner_reads_their_own_shop() {
        answering(hamra, "حفاضات", SearchDemandWeek.Kind.NONE, 9);
        signedInAs(OWNER, "MERCHANT");

        UnmetDemandResponse answer = controller.unmet(shop.getId());

        assertThat(answer.storeId()).isEqualTo(shop.getId());
        assertThat(answer.thisWeek().terms()).extracting(UnmetTermResponse::term)
                .containsExactly("حفاضات");
    }

    @Test
    @DisplayName("another merchant's shop is a 404, the same answer as a shop that does not exist")
    void another_merchants_shop_is_a_404() {
        signedInAs("somebody-else", "MERCHANT");

        assertThatThrownBy(() -> controller.unmet(shop.getId()))
                .isInstanceOf(StoreService.StoreNotFoundException.class);
    }

    @Test
    @DisplayName("a shop that is not live is a 404, for the owner and for back office alike")
    void a_draft_shop_is_a_404() {
        Store draft = new Store(OWNER, "Not Open Yet", Store.Vertical.GROCERY);
        draft.pinAt(GeoPoint.of(33.8977d, 35.4829d));
        when(stores.read(eq(draft.getId().toString()), any())).thenReturn(draft);

        signedInAs(OWNER, "MERCHANT");
        assertThatThrownBy(() -> controller.unmet(draft.getId()))
                .isInstanceOf(StoreService.StoreNotFoundException.class);

        signedInAs("backoffice-sub", "BACKOFFICE");
        assertThatThrownBy(() -> controller.unmet(draft.getId()))
                .isInstanceOf(StoreService.StoreNotFoundException.class);
    }

    @Test
    @DisplayName("back office reads any live shop")
    void backoffice_reads_any_live_shop() {
        answering(hamra, "حفاضات", SearchDemandWeek.Kind.NONE, 9);
        signedInAs("backoffice-sub", "BACKOFFICE");

        assertThat(controller.unmet(shop.getId()).thisWeek().terms()).hasSize(1);
    }

    @ParameterizedTest
    @ValueSource(strings = {"CUSTOMER", "RIDER", "MERCHANT_STAFF"})
    @DisplayName("nobody else may read it, staff included")
    void nobody_else_may_read_it(String role) {
        signedInAs("someone", role);

        assertThatThrownBy(() -> controller.unmet(shop.getId()))
                .isInstanceOf(AccessDeniedException.class);
    }

    // ------------------------------------------------------------------------------------ what

    @Test
    @DisplayName("only the shop's own areas are answered, whatever the roll-up holds elsewhere")
    void only_the_shops_own_areas_are_answered() {
        signedInAs(OWNER, "MERCHANT");
        answering(hamra, "حفاضات", SearchDemandWeek.Kind.NONE, 9);

        controller.unmet(shop.getId());

        // The ids handed to the query are the neighbourhood's, and Achrafieh is not in it.
        org.mockito.ArgumentCaptor<java.util.Collection<UUID>> areas =
                org.mockito.ArgumentCaptor.forClass(java.util.Collection.class);
        org.mockito.Mockito.verify(weeks)
                .findByWeekStartInAndAreaIdInOrderByAreaIdAscKindAscRankAsc(anyCollection(),
                        areas.capture());
        assertThat(areas.getValue()).containsExactly(hamra.getId());
        assertThat(areas.getValue()).doesNotContain(achrafieh.getId());
    }

    @Test
    @DisplayName("a shop with no neighbourhood is told so, rather than told the week was quiet")
    void no_neighbourhood_is_its_own_answer() {
        signedInAs(OWNER, "MERCHANT");
        when(zones.around(shop)).thenReturn(new DeliveryZoneService.Neighbourhood(null, null, List.of()));

        UnmetDemandResponse answer = controller.unmet(shop.getId());

        assertThat(answer.areasAround()).isZero();
        assertThat(answer.thisWeek().terms()).isEmpty();
        assertThat(answer.minimumSearches()).isEqualTo(UnmetDemand.MIN_SEARCHES);
    }

    @Test
    @DisplayName("the count is a band, never the count")
    void the_count_is_a_band() {
        signedInAs(OWNER, "MERCHANT");
        answering(hamra, "حفاضات", SearchDemandWeek.Kind.NONE, 14);

        assertThat(controller.unmet(shop.getId()).thisWeek().terms())
                .singleElement()
                .satisfies(term -> assertThat(term.about()).isEqualTo(10));
    }

    /**
     * Walks the response's shape rather than reading it, so a field added later that carried a
     * customer, a coordinate or a moment in time fails here.
     */
    @Test
    @DisplayName("nothing in the answer could name a customer, a place or a moment")
    void the_answer_says_nothing_about_who_searched() {
        List<String> fields = componentsOf(UnmetDemandResponse.class, new ArrayList<>(), 0);

        assertThat(fields).doesNotContain("accountId", "customerId", "userId", "sessionId",
                "deviceId", "latitude", "longitude", "searchedAt", "at", "searches", "count",
                "distanceMetres", "nearestMetres");
        // A week is the finest grain of time there is, and "about" is the only number.
        assertThat(fields).contains("weekStart", "about", "term", "areaName", "kind", "alreadySold");
    }

    // ------------------------------------------------------------------------------------ helpers

    /** Every record component name reachable from {@code type}, nested records included. */
    private static List<String> componentsOf(Class<?> type, List<String> found, int depth) {
        if (!type.isRecord() || depth > 4) {
            return found;
        }
        for (RecordComponent component : type.getRecordComponents()) {
            found.add(component.getName());
            Class<?> nested = component.getType();
            if (nested.isRecord()) {
                componentsOf(nested, found, depth + 1);
            } else if (List.class.isAssignableFrom(nested)
                    && component.getGenericType() instanceof java.lang.reflect.ParameterizedType p
                    && p.getActualTypeArguments()[0] instanceof Class<?> element) {
                componentsOf(element, found, depth + 1);
            }
        }
        return found;
    }

    private void answering(DeliveryZone area, String term, SearchDemandWeek.Kind kind, int searches) {
        SearchDemandWeek row = new SearchDemandWeek(calendar.weekOf(NOW), area.getId(), term, kind,
                searches, 1, NOW);
        when(weeks.findByWeekStartInAndAreaIdInOrderByAreaIdAscKindAscRankAsc(anyCollection(),
                anyCollection())).thenReturn(List.of(row));
    }

    private static DeliveryZone placed(String name, double lat, double lng) {
        DeliveryZone zone = new DeliveryZone(name, "Beirut", 10);
        zone.placeAt(GeoPoint.of(lat, lng));
        return zone;
    }

    private static Store liveShop(String merchantId) {
        Store shop = new Store(merchantId, "Corner Grocer", Store.Vertical.GROCERY);
        shop.pinAt(GeoPoint.of(33.8977d, 35.4829d));
        shop.replaceHours(Arrays.stream(DayOfWeek.values())
                .map(day -> new StoreHours(day, LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59)))
                .toList());
        TestPin.pinned(shop);
        shop.publish(Instant.parse("2026-01-01T00:00:00Z"));
        return shop;
    }

    private static void signedInAs(String subject, String... roles) {
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(subject).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt,
                Arrays.stream(roles).map(r -> new SimpleGrantedAuthority("ROLE_" + r)).toList()));
    }
}
