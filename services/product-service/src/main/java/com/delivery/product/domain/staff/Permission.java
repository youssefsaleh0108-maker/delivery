package com.delivery.product.domain.staff;

import java.util.Collections;
import java.util.EnumSet;
import java.util.Set;

/**
 * What a shop member is allowed to do.
 *
 * <p>Exactly seven values, matching the seven toggles the staff screen draws. This is the wire
 * vocabulary: it travels on {@code staff.member_changed} and is what pos-, inventory- and
 * reporting-service enforce against. Finer distinctions inside any one service stay inside that
 * service — adding an eighth value here means changing every consumer's projection, the Dart enum
 * and two localised strings, so the bar for a new one is deliberately high.
 */
public enum Permission {

    /** Ring up a sale at the register. */
    POS_SALES,
    /**
     * Reverse money: refunds, voiding a completed sale, and discounts past the store's limit.
     * The supervisor grant — separated from {@link #POS_SALES} precisely because a cashier who can
     * sell should not necessarily be able to un-sell.
     */
    POS_REFUNDS_VOIDS,
    /** Edit products, prices and stock levels. */
    MODIFY_INVENTORY_PRICING,
    /** Accept, reject and progress incoming YouDrop delivery orders. */
    MANAGE_ORDERS,
    /** See store performance: sales reports, dashboard money. */
    VIEW_REPORTS,
    /** Change general store settings — hours, delivery zones, the shop profile. */
    ACCESS_SETTINGS,
    /** Add, edit and remove other members, and edit the role permission bands. */
    MANAGE_STAFF;

    /** Every permission. What an owner holds, by definition and without a row. */
    public static Set<Permission> all() {
        return Collections.unmodifiableSet(EnumSet.allOf(Permission.class));
    }

    /**
     * The platform's starting point for a role, before the store's own band and any per-person
     * override are applied.
     *
     * <p>The two staff frames in the design disagree about what a cashier gets; per-store editing
     * is the reconciliation, so these are only defaults, not policy.
     */
    public static Set<Permission> defaultsFor(StaffRole role) {
        return switch (role) {
            case MANAGER -> all();
            case CASHIER -> Collections.unmodifiableSet(EnumSet.of(POS_SALES, MANAGE_ORDERS));
            case STOCKKEEPER -> Collections.unmodifiableSet(EnumSet.of(MODIFY_INVENTORY_PRICING));
        };
    }
}
