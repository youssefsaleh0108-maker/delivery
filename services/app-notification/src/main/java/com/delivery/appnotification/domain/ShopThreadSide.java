package com.delivery.appnotification.domain;

/** The two sides of a shop thread. The shop side is a role, not a person. */
public enum ShopThreadSide {
    CUSTOMER,
    SHOP;

    public ShopThreadSide other() {
        return this == CUSTOMER ? SHOP : CUSTOMER;
    }
}
