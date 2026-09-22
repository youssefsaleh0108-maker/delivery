package com.delivery.product.api;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.lang.reflect.RecordComponent;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import com.delivery.product.api.dto.MenuInsightsDtos.MenuInsightsResponse;
import com.delivery.product.domain.MenuViewDay;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.staff.Permission;
import com.delivery.product.domain.staff.StaffMember;
import com.delivery.product.service.MenuInsights;
import com.delivery.product.service.StaffService;
import com.delivery.product.service.StoreAccess;
import com.delivery.product.service.StoreService;

/**
 * {@code GET /api/products/menu-insights/{storeId}} — who may read what a shop's menu has been
 * doing, and what they are told.
 *
 * <p>Two things are being defended.
 *
 * <p><strong>Who.</strong> The gate is {@code VIEW_REPORTS}, not ownership, and that is the one
 * difference from the Demand Radar next door that matters: the radar is about the shop's
 * neighbours, so it admits owners alone; everything here is the shop's own page and the shop's own
 * delivered orders, so the manager trusted to run the till reads it too. A caller with no
 * relationship to the shop gets the same 404 a shop that does not exist gets, so the endpoint
 * confirms nothing about the ids it is handed.
 *
 * <p><strong>What.</strong> The response carries nothing about a reader — asserted here
 * reflectively, in the way {@code UnmetDemandAccessTest} asserts it of the radar's, so that a
 * component added later has to be thought about rather than shipped.
 */
class MenuInsightsAccessTest {

    private static final String CALLER = "merchant-sub";
    private static final UUID MINE = UUID.randomUUID();
    private static final UUID THEIRS = UUID.randomUUID();

    private final MenuInsights insights = mock(MenuInsights.class);
    private final StoreService stores = mock(StoreService.class);
    private final StaffService staff = mock(StaffService.class);

    private MenuInsightsController controller;

    @BeforeEach
    void setUp() {
        controller = new MenuInsightsController(insights, stores, staff);
        // Built before the stubbing starts, not inside a thenReturn: a mock created mid-chain
        // leaves Mockito's stubbing half-open and the next when() in any test fails instead.
        Store shop = new Store("owner-sub", "Boulangerie Antoine", Store.Vertical.GROCERY);
        MenuInsights.Report report = report();
        when(stores.read(any(), any())).thenReturn(shop);
        when(insights.forStore(any(), anyInt())).thenReturn(report);
        signedInAs(CALLER, "MERCHANT");
    }

    @AfterEach
    void signOut() {
        SecurityContextHolder.clearContext();
    }

    private static void signedInAs(String subject, String... roles) {
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(subject).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt,
                java.util.Arrays.stream(roles).map(r -> new SimpleGrantedAuthority("ROLE_" + r))
                        .toList()));
    }

    private static MenuInsights.Report report() {
        List<MenuInsights.PartOfDay> shape = new ArrayList<>();
        for (MenuViewDay.Part part : MenuViewDay.Part.values()) {
            shape.add(new MenuInsights.PartOfDay(part, new MenuInsights.Opens(0, false)));
        }
        return new MenuInsights.Report(MINE, LocalDate.of(2026, 9, 16), LocalDate.of(2026, 9, 22),
                7, new MenuInsights.Opens(40, true), new MenuInsights.Opens(20, true), shape,
                List.of(new MenuInsights.Item(UUID.randomUUID(), "Croissant", 7, 23)),
                LocalDate.of(2026, 9, 16), MenuInsights.MIN_OPENS);
    }

    private static StoreAccess memberWith(Set<Permission> permissions) {
        StaffMember member = mock(StaffMember.class);
        when(member.getUserRef()).thenReturn(CALLER);
        return StoreAccess.member(MINE, "owner-sub", member, java.util.EnumSet.copyOf(
                permissions.isEmpty() ? java.util.EnumSet.noneOf(Permission.class)
                        : java.util.EnumSet.copyOf(permissions)));
    }

    // ------------------------------------------------------------------------------------ who

    @Test
    @DisplayName("the owner reads their own shop")
    void theOwnerReadsTheirOwnShop() {
        when(staff.accessFor(MINE, CALLER)).thenReturn(StoreAccess.owner(MINE, CALLER));

        MenuInsightsResponse answer = controller.insights(MINE, 7);

        assertThat(answer.storeId()).isEqualTo(MINE);
        assertThat(answer.opens().about()).isEqualTo(40);
    }

    @Test
    @DisplayName("another merchant's shop is a 404, the same answer a shop that is not there gives")
    void somebodyElsesShopIsNotFound() {
        when(staff.accessFor(THEIRS, CALLER)).thenReturn(StoreAccess.none());

        assertThatThrownBy(() -> controller.insights(THEIRS, 7))
                .isInstanceOf(StoreStaffController.StoreNotVisibleException.class);

        verify(insights, never()).forStore(any(), anyInt());
    }

    @Test
    @DisplayName("a member trusted with reports reads it, unlike the radar next door")
    void aMemberWithViewReportsReadsIt() {
        // Built first, then stubbed: memberWith stubs a mock of its own, and doing that inside a
        // thenReturn would leave this when() half-open.
        StoreAccess manager = memberWith(Set.of(Permission.VIEW_REPORTS));
        when(staff.accessFor(MINE, CALLER)).thenReturn(manager);

        assertThat(controller.insights(MINE, 7).storeId()).isEqualTo(MINE);
    }

    @Test
    @DisplayName("a member without it is refused as staff, not hidden from as a stranger")
    void aMemberWithoutViewReportsIsRefused() {
        StoreAccess cashier = memberWith(Set.of(Permission.POS_SALES));
        when(staff.accessFor(MINE, CALLER)).thenReturn(cashier);
        assertThat(cashier.isAnything()).isTrue();

        // The roster's own refusal, and deliberately not a 404: they are already known to be staff
        // of this shop, so hiding it from them would be a lie the next screen disproves.
        assertThatThrownBy(() -> controller.insights(MINE, 7))
                .isInstanceOf(StoreAccess.StoreAccessDeniedException.class);

        verify(insights, never()).forStore(any(), anyInt());
    }

    @Test
    @DisplayName("the back office reads any shop without a roster row")
    void theBackOfficeReadsAnyShop() {
        signedInAs("backoffice-sub", "BACKOFFICE");

        assertThat(controller.insights(THEIRS, 7).storeId()).isEqualTo(MINE);

        verify(staff, never()).accessFor(any(), any());
    }

    @Test
    @DisplayName("the window comes from the request and is handed on to be clamped, not refused")
    void theWindowIsPassedThrough() {
        when(staff.accessFor(MINE, CALLER)).thenReturn(StoreAccess.owner(MINE, CALLER));

        controller.insights(MINE, 365);

        verify(insights).forStore(any(), eq(365));
    }

    // ----------------------------------------------------------------------------------- what

    @Test
    @DisplayName("the answer says nothing about who read the menu")
    void theAnswerSaysNothingAboutWho() {
        when(staff.accessFor(MINE, CALLER)).thenReturn(StoreAccess.owner(MINE, CALLER));

        MenuInsightsResponse answer = controller.insights(MINE, 7);

        List<String> components = new ArrayList<>();
        collect(answer.getClass(), components);

        assertThat(components).doesNotContain("accountId", "customerId", "userId", "sessionId",
                "deviceId", "ip", "ipAddress", "userAgent", "referrer", "latitude", "longitude",
                "openedAt", "viewedAt", "timestamp", "hour", "minute", "country", "language");
        // No exact count of opens is served under any name — only the band, and whether the floor
        // was cleared at all.
        assertThat(components).doesNotContain("views", "opensCount", "count", "exact", "scans",
                "qrScans");
        assertThat(components).contains("about", "enough", "minimumOpens");
    }

    @Test
    @DisplayName("the parts of the day are named, and carry no clock times with them")
    void thePartsCarryNoTimes() {
        when(staff.accessFor(MINE, CALLER)).thenReturn(StoreAccess.owner(MINE, CALLER));

        MenuInsightsResponse answer = controller.insights(MINE, 7);

        assertThat(answer.shape()).extracting(p -> p.part())
                .containsExactly("MORNING", "MIDDAY", "EVENING", "NIGHT");
        // The hours each part covers are the server's to decide and the client's to name. Sending
        // them would be sending a clock into a response that has deliberately not got one.
        assertThat(answer.shape().get(0).getClass().getRecordComponents())
                .extracting(RecordComponent::getName)
                .containsExactlyInAnyOrder("part", "opens");
    }

    /** Every record component name reachable from the response, so a nested one cannot hide. */
    private static void collect(Class<?> type, List<String> into) {
        if (!type.isRecord()) {
            return;
        }
        for (RecordComponent component : type.getRecordComponents()) {
            into.add(component.getName());
            Class<?> nested = component.getType();
            if (nested.isRecord()) {
                collect(nested, into);
            } else if (List.class.isAssignableFrom(nested)
                    && component.getGenericType() instanceof java.lang.reflect.ParameterizedType p
                    && p.getActualTypeArguments()[0] instanceof Class<?> element) {
                collect(element, into);
            }
        }
    }

    @Test
    @DisplayName("nothing in the response is called a scan")
    void nothingIsCalledAScan() {
        // The shop's counter QR encodes the page's plain address, so a scan of it and a tapped
        // link are the same request. A field called "scans" would be a number the platform cannot
        // compute, which is worse than one it has not got.
        List<String> components = new ArrayList<>();
        collect(MenuInsightsResponse.class, components);

        assertThat(components).noneMatch(name -> name.toLowerCase(Locale.ROOT).contains("scan"));
        assertThat(components).contains("fromTableCodes");
    }
}
