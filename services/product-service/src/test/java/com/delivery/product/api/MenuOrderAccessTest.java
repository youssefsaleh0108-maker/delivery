package com.delivery.product.api;

import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import com.delivery.product.api.StoreCategoryController.ProductOrderRequest;
import com.delivery.product.domain.staff.Permission;
import com.delivery.product.domain.staff.StaffMember;
import com.delivery.product.service.StaffService;
import com.delivery.product.service.StoreAccess;
import com.delivery.product.service.StoreCategoryService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Who may arrange a shop's menu.
 *
 * <p>The menu builder is a screen a merchant with two shops opens twice, once per shop, and the
 * thing that must never happen is a drag in one arriving at the other. So the endpoint is scoped by
 * the store in its own path and gated by the same permission the sections beside it are gated by —
 * and a caller with no relationship to the shop gets the 404 an id that was never issued gets,
 * rather than a 403 that would confirm the shop exists.
 */
@DisplayName("arranging a shop's menu")
class MenuOrderAccessTest {

    private static final UUID MINE = UUID.randomUUID();
    private static final UUID THEIRS = UUID.randomUUID();
    private static final UUID SECTION = UUID.randomUUID();
    private static final String CALLER = "caller-sub";

    private StaffService staff;
    private StoreCategoryService sections;
    private StoreCategoryController controller;

    @BeforeEach
    void signIn() {
        staff = mock(StaffService.class);
        sections = mock(StoreCategoryService.class);
        controller = new StoreCategoryController(sections, staff);

        Jwt token = Jwt.withTokenValue("token").header("alg", "none").subject(CALLER).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(token));
    }

    @AfterEach
    void signOut() {
        SecurityContextHolder.clearContext();
    }

    @Test
    @DisplayName("a merchant arranges the shop they are looking at, by its own path")
    void arrangesTheShopInThePath() {
        when(staff.accessFor(MINE, CALLER)).thenReturn(StoreAccess.owner(MINE, CALLER));
        List<UUID> order = List.of(UUID.randomUUID(), UUID.randomUUID());
        when(sections.reorderProducts(eq(MINE), eq(SECTION), any())).thenReturn(List.of());

        controller.reorderProducts(MINE, SECTION, new ProductOrderRequest(order));

        // The store in the path, not "the merchant's first shop": a merchant with two shops drags
        // in the one they opened.
        verify(sections).reorderProducts(MINE, SECTION, order);
    }

    @Test
    @DisplayName("another merchant's shop is a 404, and nothing is written")
    void somebodyElsesShopIsNotFound() {
        // No relationship at all — which is what a merchant sees of a shop that is not theirs.
        when(staff.accessFor(THEIRS, CALLER)).thenReturn(StoreAccess.none());

        assertThatThrownBy(() -> controller.reorderProducts(THEIRS, SECTION,
                new ProductOrderRequest(List.of(UUID.randomUUID()))))
                .isInstanceOf(StoreStaffController.StoreNotVisibleException.class);

        verify(sections, never()).reorderProducts(any(), any(), any());
    }

    @Test
    @DisplayName("an employee who may not price the shelves may not arrange them either")
    void needsThePermissionThatMovesPrices() {
        // A member of the shop, but not one who may change what is on sale or for how much. The
        // order of a menu is exactly that kind of change.
        StaffMember cashier = mock(StaffMember.class);
        when(cashier.getUserRef()).thenReturn(CALLER);
        StoreAccess readOnly = StoreAccess.member(MINE, "owner-sub", cashier, java.util.Set.of());
        when(staff.accessFor(MINE, CALLER)).thenReturn(readOnly);
        assertThat(readOnly.isAnything()).isTrue();

        assertThatThrownBy(() -> controller.reorderProducts(MINE, SECTION,
                new ProductOrderRequest(List.of(UUID.randomUUID()))))
                .isInstanceOf(StoreAccess.StoreAccessDeniedException.class);

        verify(sections, never()).reorderProducts(any(), any(), any());
    }

    @Test
    @DisplayName("the permission is the one the sections beside it keep")
    void theSamePermissionAsTheSections() {
        // Not a new one. A stockkeeper arranging shelves is doing their job, and the row and what
        // is on it are the same job.
        assertThat(Permission.MODIFY_INVENTORY_PRICING).isNotNull();
        when(staff.accessFor(MINE, CALLER)).thenReturn(StoreAccess.owner(MINE, CALLER));
        when(sections.reorderProducts(any(), any(), any())).thenReturn(List.of());

        controller.reorderProducts(MINE, SECTION, new ProductOrderRequest(List.of(UUID.randomUUID())));
        controller.reorder(MINE, new StoreCategoryController.ReorderRequest(List.of(SECTION)));
    }
}
