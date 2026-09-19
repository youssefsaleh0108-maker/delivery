package com.delivery.onboarding.service;

import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.AbstractPlatformTransactionManager;
import org.springframework.transaction.support.DefaultTransactionStatus;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * Transactions with no database behind them, which still mark themselves active while they are open
 * and count how each one ended — as much as a real transaction manager would let a test see.
 *
 * <p>This module's suites load no Spring context and mock every repository, so a mocked save
 * "succeeds" wherever it runs, and whether a call ran inside a transaction, or which transaction
 * rolled back, is invisible. {@link #where(String)}, called from a mocked collaborator, records the
 * first; the counts say the second. app-notification's suites use the same arrangement.
 */
final class TransactionsWithoutADatabase extends AbstractPlatformTransactionManager {

    private int begun;
    private int committed;
    private int rolledBack;

    /** "{@code what} inside a transaction" or "{@code what} outside a transaction", as it is now. */
    static String where(String what) {
        return what + (TransactionSynchronizationManager.isActualTransactionActive()
                ? " inside a transaction" : " outside a transaction");
    }

    int begun() {
        return begun;
    }

    int committed() {
        return committed;
    }

    int rolledBack() {
        return rolledBack;
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
        committed++;
    }

    @Override
    protected void doRollback(DefaultTransactionStatus status) {
        rolledBack++;
    }
}
