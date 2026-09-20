package com.delivery.product.service;

import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.AbstractPlatformTransactionManager;
import org.springframework.transaction.support.DefaultTransactionStatus;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * Transactions with no database behind them, which still mark themselves active while they are open,
 * exactly as a real transaction manager does. The same helper app-notification's suite uses, for the
 * same reason.
 *
 * <p>This suite loads no Spring context, so without it a test could not tell a call a service makes
 * inside its transaction from one it makes before or after. {@link #where(String)}, called from a
 * mocked collaborator, records which it was. A merchant's find by photo depends on the difference at
 * both ends: the read of their catalogue must be inside one, so {@code SET LOCAL statement_timeout}
 * binds it, and the call to the provider must be outside one, because a pooled connection held across
 * a twenty-five second call is one taken from every storefront.
 */
final class TransactionsWithoutADatabase extends AbstractPlatformTransactionManager {

    private int begun;

    /** "{@code what} inside a transaction" or "{@code what} outside a transaction", as it is now. */
    static String where(String what) {
        return what + (TransactionSynchronizationManager.isActualTransactionActive()
                ? " inside a transaction" : " outside a transaction");
    }

    /** Whether a transaction is open right now. */
    static boolean inATransaction() {
        return TransactionSynchronizationManager.isActualTransactionActive();
    }

    /** How many transactions have begun. */
    int begun() {
        return begun;
    }

    @Override
    protected Object doGetTransaction() {
        // Any object will do: a transaction is active while its status holds one.
        return new Object();
    }

    @Override
    protected void doBegin(Object transaction, TransactionDefinition definition) {
        begun++;
    }

    @Override
    protected void doCommit(DefaultTransactionStatus status) {
        // Nothing to commit.
    }

    @Override
    protected void doRollback(DefaultTransactionStatus status) {
        // Nothing to roll back.
    }
}
