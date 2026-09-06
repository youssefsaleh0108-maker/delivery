package com.delivery.product.domain.staff;

/**
 * The job a member does at a shop.
 *
 * <p>OWNER is absent on purpose: ownership is {@code stores.merchant_id == sub}, not a row in
 * {@code staff_members}. Making the owner a row would create a way to demote or delete them out of
 * their own shop.
 */
public enum StaffRole {

    /** Runs the shop day to day. Holds everything the owner does, but can be removed. */
    MANAGER,
    /** Works the register. */
    CASHIER,
    /** Handles goods: receiving, counts, stock adjustments. */
    STOCKKEEPER
}
