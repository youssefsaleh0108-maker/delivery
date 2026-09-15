package com.delivery.appnotification.service;

import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.AbstractPlatformTransactionManager;
import org.springframework.transaction.support.DefaultTransactionStatus;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * Transactions with no database behind them, which still mark themselves active while they are open,
 * exactly as a real transaction manager does.
 *
 * <p>This suite loads no Spring context, so without it a test could not tell a call a service makes
 * inside its transaction from one it makes before: {@link #where(String)}, called from a mocked
 * collaborator, records which it was. Opening a shop thread and confirming a shop's owner both depend
 * on the difference, because a remote read made inside a transaction holds one of the pool's
 * connections for as long as the other service takes to answer.
 */
final class TransactionsWithoutADatabase extends AbstractPlatformTransactionManager {

    private int begun;

    /** "{@code what} inside a transaction" or "{@code what} outside a transaction", as it is now. */
    static String where(String what) {
        return what + (TransactionSynchronizationManager.isActualTransactionActive()
                ? " inside a transaction" : " outside a transaction");
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
