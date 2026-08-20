package com.delivery.accounting.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.TestPropertySource;

import jakarta.persistence.EntityManager;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The stuck-settlement queries, run against a real Postgres.
 *
 * <p>These could not be checked with mocks. What is under test <em>is</em> the SQL: an correlated
 * {@code not exists} over enum-typed columns, which either parses and means what it should or does
 * neither, and a mocked repository would happily answer whatever it was told regardless. The figure
 * it produces is the one that decides whether somebody is woken up because a customer has paid for
 * goods nobody has been paid for, so "it compiles" is not enough.
 *
 * <p><strong>Skipped unless a database is there.</strong> Guarded on a property rather than assumed,
 * so {@code mvn test} stays green on a machine with no Docker while still being runnable on one that
 * has:
 *
 * <pre>
 * docker run --rm -d --name acct -p 55433:5432 -e POSTGRES_PASSWORD=test -e POSTGRES_DB=accounting postgres:17
 * # apply platform V1/V2/V50 and accounting V40-V44, then:
 * mvn -pl services/accounting-service test -Ddelivery.test.postgres=true
 * </pre>
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:postgresql://localhost:55433/accounting",
        "spring.datasource.username=postgres",
        "spring.datasource.password=test",
        "spring.flyway.enabled=false",
        "spring.jpa.hibernate.ddl-auto=none"
})
@org.junit.jupiter.api.condition.EnabledIfSystemProperty(
        named = "delivery.test.postgres", matches = "true")
class SettlementHealthQueryTest {

    @Autowired
    private AccountingTransactionRepository transactions;

    @Autowired
    private EntityManager entityManager;

    private static final Instant LONG_AGO = Instant.now().minus(1, ChronoUnit.HOURS);
    private static final Instant THRESHOLD = Instant.now().minus(5, ChronoUnit.MINUTES);

    @BeforeEach
    void clean() {
        entityManager.createQuery("delete from AccountingTransaction").executeUpdate();
        entityManager.flush();
    }

    /**
     * Writes a leg directly, because the entity's own lifecycle will not produce the states this
     * needs — a leg that has been PENDING for an hour cannot be created by waiting.
     */
    private AccountingTransaction leg(UUID orderId, AccountingTransaction.Leg legKind,
                                      AccountingTransaction.Status status, Instant createdAt,
                                      Instant postedAt) {
        // Schema-qualified. The entity is mapped to accounting.transactions, and an unqualified
        // name here resolves through search_path instead — writing to a different table than the
        // query under test reads, which looks exactly like a query that finds nothing.
        entityManager.createNativeQuery("""
                INSERT INTO accounting.transactions
                    (id, order_id, leg, account_ref, amount, currency, direction, status,
                     attempts, created_at, posted_at)
                VALUES (?1, ?2, ?3, 'ACC-1', 42.50, 'USD', ?4, ?5, 0, ?6, ?7)
                """)
                .setParameter(1, UUID.randomUUID())
                .setParameter(2, orderId)
                .setParameter(3, legKind.name())
                .setParameter(4, legKind == AccountingTransaction.Leg.CUSTOMER_DEBIT
                        ? "DEBIT" : "CREDIT")
                .setParameter(5, status.name())
                // Bound as OffsetDateTime rather than Instant: a native query hands the value
                // straight to JDBC, which has no mapping for Instant against timestamptz and
                // quietly stores something other than what was asked for.
                .setParameter(6, createdAt.atOffset(java.time.ZoneOffset.UTC))
                .setParameter(7, postedAt == null ? null : postedAt.atOffset(java.time.ZoneOffset.UTC))
                .executeUpdate();
        entityManager.flush();
        entityManager.clear();
        return null;
    }

    private long uncredited() {
        return transactions.countDebitedWithoutCounterpartOlderThan(THRESHOLD);
    }

    @Nested
    @DisplayName("orders debited with nothing credited")
    class DebitedWithoutCounterpart {

        /** The state worth waking somebody for: the customer paid and nobody was paid. */
        @Test
        void a_posted_debit_with_no_credit_at_all_is_counted() {
            UUID order = UUID.randomUUID();
            leg(order, AccountingTransaction.Leg.CUSTOMER_DEBIT,
                    AccountingTransaction.Status.POSTED, LONG_AGO, LONG_AGO);

            assertThat(uncredited()).isEqualTo(1);
        }

        @Test
        void a_debit_whose_merchant_credit_posted_is_not_counted() {
            UUID order = UUID.randomUUID();
            leg(order, AccountingTransaction.Leg.CUSTOMER_DEBIT,
                    AccountingTransaction.Status.POSTED, LONG_AGO, LONG_AGO);
            leg(order, AccountingTransaction.Leg.MERCHANT_CREDIT,
                    AccountingTransaction.Status.POSTED, LONG_AGO, LONG_AGO);

            assertThat(uncredited()).isZero();
        }

        /** An errand pays the rider, not a merchant — equally discharged. */
        @Test
        void a_rider_credit_discharges_it_too() {
            UUID order = UUID.randomUUID();
            leg(order, AccountingTransaction.Leg.CUSTOMER_DEBIT,
                    AccountingTransaction.Status.POSTED, LONG_AGO, LONG_AGO);
            leg(order, AccountingTransaction.Leg.RIDER_CREDIT,
                    AccountingTransaction.Status.POSTED, LONG_AGO, LONG_AGO);

            assertThat(uncredited()).isZero();
        }

        /** An order that was unwound is resolved, not stuck — the customer has their money back. */
        @Test
        void a_refund_discharges_it() {
            UUID order = UUID.randomUUID();
            leg(order, AccountingTransaction.Leg.CUSTOMER_DEBIT,
                    AccountingTransaction.Status.POSTED, LONG_AGO, LONG_AGO);
            leg(order, AccountingTransaction.Leg.CUSTOMER_REFUND,
                    AccountingTransaction.Status.POSTED, LONG_AGO, LONG_AGO);

            assertThat(uncredited()).isZero();
        }

        /**
         * The case the whole query exists for. A credit that is itself still PENDING has not
         * discharged anything — the merchant has not been paid, and counting it as resolved would
         * hide precisely the failure being looked for.
         */
        @Test
        void a_credit_that_is_still_pending_does_not_discharge_it() {
            UUID order = UUID.randomUUID();
            leg(order, AccountingTransaction.Leg.CUSTOMER_DEBIT,
                    AccountingTransaction.Status.POSTED, LONG_AGO, LONG_AGO);
            leg(order, AccountingTransaction.Leg.MERCHANT_CREDIT,
                    AccountingTransaction.Status.PENDING, LONG_AGO, null);

            assertThat(uncredited()).isEqualTo(1);
        }

        @Test
        void a_credit_that_failed_does_not_discharge_it() {
            UUID order = UUID.randomUUID();
            leg(order, AccountingTransaction.Leg.CUSTOMER_DEBIT,
                    AccountingTransaction.Status.POSTED, LONG_AGO, LONG_AGO);
            leg(order, AccountingTransaction.Leg.MERCHANT_CREDIT,
                    AccountingTransaction.Status.FAILED, LONG_AGO, null);

            assertThat(uncredited()).isEqualTo(1);
        }

        /** A reversal is the saga working. The debit is no longer POSTED, so nothing is stuck. */
        @Test
        void a_compensated_debit_is_not_counted() {
            UUID order = UUID.randomUUID();
            leg(order, AccountingTransaction.Leg.CUSTOMER_DEBIT,
                    AccountingTransaction.Status.COMPENSATED, LONG_AGO, LONG_AGO);

            assertThat(uncredited()).isZero();
        }

        /** A debit still in flight has not taken anyone's money yet. */
        @Test
        void a_pending_debit_is_not_counted() {
            UUID order = UUID.randomUUID();
            leg(order, AccountingTransaction.Leg.CUSTOMER_DEBIT,
                    AccountingTransaction.Status.PENDING, LONG_AGO, null);

            assertThat(uncredited()).isZero();
        }

        /** Cash never touches a bank, so it can never be in this state. */
        @Test
        void a_cash_order_is_never_counted() {
            UUID order = UUID.randomUUID();
            leg(order, AccountingTransaction.Leg.CASH_COLLECTED,
                    AccountingTransaction.Status.SETTLED_IN_CASH, LONG_AGO, LONG_AGO);

            assertThat(uncredited()).isZero();
        }

        /** A settlement seconds old is in flight, not stuck. The threshold is the whole point. */
        @Test
        void a_debit_inside_the_threshold_is_not_counted_yet() {
            UUID order = UUID.randomUUID();
            leg(order, AccountingTransaction.Leg.CUSTOMER_DEBIT,
                    AccountingTransaction.Status.POSTED, Instant.now(), Instant.now());

            assertThat(uncredited()).isZero();
        }

        /** Counted per order, not per leg, so one order cannot inflate the figure. */
        @Test
        void each_affected_order_counts_once() {
            UUID first = UUID.randomUUID();
            UUID second = UUID.randomUUID();
            leg(first, AccountingTransaction.Leg.CUSTOMER_DEBIT,
                    AccountingTransaction.Status.POSTED, LONG_AGO, LONG_AGO);
            leg(second, AccountingTransaction.Leg.CUSTOMER_DEBIT,
                    AccountingTransaction.Status.POSTED, LONG_AGO, LONG_AGO);
            // A commission leg is not a counterpart — the platform paying itself discharges nothing.
            leg(second, AccountingTransaction.Leg.PLATFORM_COMMISSION,
                    AccountingTransaction.Status.POSTED, LONG_AGO, LONG_AGO);

            assertThat(uncredited()).isEqualTo(2);
        }

        @Test
        void a_healthy_ledger_reports_nothing() {
            assertThat(uncredited()).isZero();
        }
    }

    @Nested
    @DisplayName("legs the saga is still waiting on")
    class StuckLegs {

        private long stuck() {
            return transactions.countByStatusAndCreatedAtBefore(
                    AccountingTransaction.Status.PENDING, THRESHOLD);
        }

        @Test
        void an_old_pending_leg_is_counted() {
            leg(UUID.randomUUID(), AccountingTransaction.Leg.MERCHANT_CREDIT,
                    AccountingTransaction.Status.PENDING, LONG_AGO, null);

            assertThat(stuck()).isEqualTo(1);
        }

        @Test
        void a_recent_pending_leg_is_not() {
            leg(UUID.randomUUID(), AccountingTransaction.Leg.MERCHANT_CREDIT,
                    AccountingTransaction.Status.PENDING, Instant.now(), null);

            assertThat(stuck()).isZero();
        }

        @Test
        void a_posted_leg_is_never_counted_however_old() {
            leg(UUID.randomUUID(), AccountingTransaction.Leg.MERCHANT_CREDIT,
                    AccountingTransaction.Status.POSTED, LONG_AGO, LONG_AGO);

            assertThat(stuck()).isZero();
        }
    }
}
