package com.delivery.corebanking.simulator.domain;

import java.time.Instant;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

/**
 * A fake account with a real balance.
 *
 * <p>Balances are held in minor units as a {@code long}, never a decimal or a double. That is what
 * a real core banking system does, and mirroring it here means the connector's rounding is
 * exercised against the same representation the bank will use rather than a friendlier one.
 */
@Entity
@Table(name = "bank_accounts")
public class BankAccount {

    public enum Status { ACTIVE, FROZEN, CLOSED }

    @Id
    @Column(name = "account_ref", nullable = false, updatable = false, length = 64)
    private String accountRef;

    @Column(name = "holder_name", nullable = false, length = 255)
    private String holderName;

    @Column(name = "balance_minor", nullable = false)
    private long balanceMinor;

    @Column(name = "currency", nullable = false, length = 3)
    private String currency;

    @jakarta.persistence.Enumerated(jakarta.persistence.EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status = Status.ACTIVE;

    @Column(name = "opened_at", nullable = false, insertable = false, updatable = false)
    private Instant openedAt;

    /**
     * Optimistic locking on the balance.
     *
     * <p>Two postings against one account arriving together is the normal case here — a settlement
     * credits the platform account for every order in flight. Without this, a lost update would
     * silently lose money, which is precisely the bug a bank simulator must not have if it is going
     * to be trusted as a test oracle.
     */
    @Version
    @Column(name = "version")
    private Long version;

    protected BankAccount() {
        // for JPA
    }

    public boolean canPost() {
        return status == Status.ACTIVE;
    }

    public boolean hasFunds(long amountMinor) {
        return balanceMinor >= amountMinor;
    }

    public void debit(long amountMinor) {
        balanceMinor -= amountMinor;
    }

    public void credit(long amountMinor) {
        balanceMinor += amountMinor;
    }

    public String getAccountRef() {
        return accountRef;
    }

    public String getHolderName() {
        return holderName;
    }

    public long getBalanceMinor() {
        return balanceMinor;
    }

    public String getCurrency() {
        return currency;
    }

    public Status getStatus() {
        return status;
    }

    public Instant getOpenedAt() {
        return openedAt;
    }
}
