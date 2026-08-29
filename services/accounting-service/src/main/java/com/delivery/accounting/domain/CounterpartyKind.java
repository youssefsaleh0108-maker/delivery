package com.delivery.accounting.domain;

/**
 * The sort of party a ledger leg belongs to.
 *
 * <p><strong>Not the same question as {@code account_ref}.</strong> An account is where money would
 * be posted; this is who the money is about. The two legitimately disagree — two shops can share a
 * payout account, one shop can change theirs mid-month, and today every merchant credit in the
 * database points at a single omnibus account because nobody has a {@code bankAccountRef} on file.
 * Reading identity out of an account number is what made that omnibus bucket look correct for as
 * long as it did.
 *
 * <p>There is deliberately no {@code CUSTOMER}. A customer is the other side of a collection, not a
 * party the platform settles with, and inventing a kind for them would put every order in the
 * counterparties listing.
 */
public enum CounterpartyKind {

    /** A shop. Owed the goods it sold, less the platform's commission. */
    MERCHANT,

    /**
     * A person who carries orders.
     *
     * <p>Both directions at once, which is why the rider statement is the awkward one: they are owed
     * their earnings and they owe the platform every note they took at the door and have not yet
     * banked.
     */
    RIDER,

    /** A delivery company. Owed the delivery fees on its jobs, less the platform's cut. */
    CARRIER,

    /** The platform itself. */
    PLATFORM;

    /**
     * The reference used on every {@link #PLATFORM} leg.
     *
     * <p>A constant rather than an id, because the platform is not a row in any directory — there is
     * exactly one of it, and giving it a generated identifier would mean the commission legs from
     * before and after some deployment could not be added together.
     *
     * <p>Deliberately not {@code delivery.accounting.platform-account}: that is a bank account, it
     * is configurable per environment, and a statement that changed identity when somebody edited a
     * property file would silently split the platform's own history in two.
     */
    public static final String PLATFORM_REF = "PLATFORM";

    /** Parses a path parameter, case-insensitively, without throwing on rubbish. */
    public static CounterpartyKind parse(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        for (CounterpartyKind kind : values()) {
            if (kind.name().equalsIgnoreCase(value.trim())) {
                return kind;
            }
        }
        return null;
    }
}
