package com.delivery.product.api;

import java.util.UUID;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.product.api.dto.MenuInsightsDtos.MenuInsightsResponse;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.staff.Permission;
import com.delivery.product.service.MenuInsights;
import com.delivery.product.service.StaffService;
import com.delivery.product.service.StoreAccess;
import com.delivery.product.service.StoreService;

/**
 * What a shop's own menu has been doing: {@code GET /api/products/menu-insights/{storeId}}.
 *
 * <p>Under {@code /api/products} beside the demand read, and {@code menu-insights} is a literal
 * segment, which Spring prefers to {@code ProductController}'s {@code /{id}} exactly as
 * {@code demand}, {@code search} and {@code scans} are.
 *
 * <p><strong>Gated on {@code VIEW_REPORTS}, and not on ownership alone.</strong> This is the one
 * place that rule is right, and the difference from {@code UnmetDemandController} next door is
 * worth stating. The Demand Radar is about the shop's <em>neighbours</em> — people who never
 * ordered from it — so it admits owners only and refuses staff outright. Everything here is the
 * shop's own: its page, its opens, its delivered orders. A manager trusted to run the till and
 * count the stock is exactly who reads it, and {@code VIEW_REPORTS} has been in
 * {@link Permission} waiting for something to guard since the roster shipped.
 *
 * <p>A caller with no relationship to the shop gets 404, not 403 — the same answer as a shop that
 * does not exist, so the endpoint confirms nothing about the ids it is handed. A member without
 * {@code VIEW_REPORTS} gets the roster's own refusal, because they are already known to be staff
 * and hiding the shop from them would be a lie they can disprove from the next screen.
 *
 * <p>The window comes from the request and is clamped rather than refused
 * ({@link MenuInsights#MAX_DAYS}); the response repeats the window it actually used, so a screen
 * asking for a year draws a month and says "30 days" instead of showing an error.
 */
@RestController
@RequestMapping("/api/products/menu-insights")
public class MenuInsightsController {

    private final MenuInsights insights;
    private final StoreService stores;
    private final StaffService staff;

    public MenuInsightsController(MenuInsights insights, StoreService stores, StaffService staff) {
        this.insights = insights;
        this.stores = stores;
        this.staff = staff;
    }

    /**
     * One shop's menu over the last {@code days} of its own calendar.
     *
     * <p>Empty panels are the ordinary answer for a quiet shop, and the response carries
     * {@code minimumOpens} and {@code countingSince} so the screen can say which silence it is in:
     * too few readers to report, or counting that started after the shop's page did.
     */
    @GetMapping("/{storeId}")
    @PreAuthorize("isAuthenticated()")
    public MenuInsightsResponse insights(
            @PathVariable UUID storeId,
            @RequestParam(name = "days", defaultValue = "" + MenuInsights.DEFAULT_DAYS) int days) {
        Store store = stores.read(storeId.toString(), null);
        if (!CurrentUser.hasRole("BACKOFFICE")) {
            StoreAccess access = staff.accessFor(storeId, CurrentUser.requireId());
            if (!access.isAnything()) {
                throw new StoreStaffController.StoreNotVisibleException(storeId);
            }
            access.require(Permission.VIEW_REPORTS);
        }
        return MenuInsightsResponse.of(insights.forStore(store, days));
    }
}
