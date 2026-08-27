package com.delivery.accounting.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.test.context.TestPropertySource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The two indexes the rider ledger's safety actually rests on, run against a real Postgres.
 *
 * <p>These cannot be checked with mocks, and the rest of the rider test suite says so explicitly:
 * {@code RiderCashOutTest} emulates the constraint to prove the service handles it correctly, and
 * {@code RiderJobEarningTest} proves a violation is treated as the no-op it is. Neither can prove
 * the index exists, is spelled correctly, or is partial on the right predicate — and if it is not,
 * every one of those tests still passes while two concurrent cash-outs both succeed in production.
 *
 * <p>What is under test <em>is</em> the DDL. The figures behind it are a rider's pay and the money
 * the platform hands over, so "it compiles" is not enough.
 *
 * <p><strong>Skipped unless a database is there</strong>, exactly like
 * {@link SettlementHealthQueryTest}, so {@code mvn test} stays green on a machine with no Docker
 * while still being runnable on one that has:
 *
 * <pre>
 * docker run --rm -d --name acct -p 55433:5432 -e POSTGRES_PASSWORD=test -e POSTGRES_DB=accounting postgres:17
 * # apply platform V1/V2/V50 and accounting V40-V46, then:
 * mvn -f services/accounting-service/pom.xml test -Ddelivery.test.postgres=true
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
@DisplayName("the indexes the rider ledger's safety rests on")
class RiderLedgerConstraintTest {

    @Autowired
    private RiderLedgerRepository ledger;

    @Autowired
    private RiderCashOutRepository cashOuts;

    private static RiderLedgerEntry job(String riderRef, UUID orderId) {
        return RiderLedgerEntry.jobEarning(riderRef, orderId, new BigDecimal("2.25"), "USD",
                RiderLedgerEntry.Fleet.PLATFORM, null, "customer-1", Instant.now());
    }

    @Test
    void one_rider_cannot_earn_twice_on_one_order() {
        // The redelivery guarantee. Without this index the second copy of order.delivered pays the
        // rider again, and the bus promises there will be a second copy.
        UUID orderId = UUID.randomUUID();
        ledger.saveAndFlush(job("rider-1", orderId));

        assertThatThrownBy(() -> ledger.saveAndFlush(job("rider-1", orderId)))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void but_a_job_a_reimbursement_and_a_tip_on_one_order_are_all_allowed() {
        // Keyed on the entry type as well, because one errand legitimately produces all three.
        UUID orderId = UUID.randomUUID();
        ledger.saveAndFlush(job("rider-2", orderId));

        assertThatCode(() -> {
            ledger.saveAndFlush(RiderLedgerEntry.reimbursement("rider-2", orderId,
                    new BigDecimal("25.00"), "USD", RiderLedgerEntry.Fleet.PLATFORM, null,
                    Instant.now()));
            ledger.saveAndFlush(RiderLedgerEntry.tip("rider-2", orderId, new BigDecimal("3.00"),
                    "USD", RiderLedgerEntry.Fleet.PLATFORM, null, true, Instant.now()));
        }).doesNotThrowAnyException();
    }

    @Test
    void two_riders_on_one_order_do_not_collide() {
        // A reassigned drop is one order and two riders, and the index must not turn that into a
        // constraint violation that fails a settlement.
        UUID orderId = UUID.randomUUID();
        ledger.saveAndFlush(job("rider-3", orderId));

        assertThatCode(() -> ledger.saveAndFlush(job("rider-4", orderId)))
                .doesNotThrowAnyException();
    }

    @Test
    void cash_out_movements_carry_no_order_and_are_never_deduplicated_against_each_other() {
        // The index is partial on order_id IS NOT NULL. Without that, a rider's second cash-out
        // hold would collide with their first and they could never take money out twice.
        assertThatCode(() -> {
            ledger.saveAndFlush(RiderLedgerEntry.cashOutHeld("rider-5", UUID.randomUUID(),
                    new BigDecimal("10.00"), "USD"));
            ledger.saveAndFlush(RiderLedgerEntry.cashOutHeld("rider-5", UUID.randomUUID(),
                    new BigDecimal("10.00"), "USD"));
        }).doesNotThrowAnyException();
    }

    @Test
    void a_rider_can_only_have_one_cash_out_waiting_at_a_time() {
        // THE line the concurrency argument rests on. Two simultaneous requests both pass the
        // balance check; this is what stops the second one existing.
        cashOuts.saveAndFlush(new RiderCashOut("rider-6", new BigDecimal("20.00"), "USD", "wallet"));

        assertThatThrownBy(() -> cashOuts.saveAndFlush(
                new RiderCashOut("rider-6", new BigDecimal("5.00"), "USD", "wallet")))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void and_can_ask_again_once_the_first_one_is_settled() {
        // Partial on status = 'REQUESTED', so PAID and REJECTED release the rider immediately. An
        // index over every row would lock a rider out of the button forever after one payout.
        RiderCashOut first =
                new RiderCashOut("rider-7", new BigDecimal("20.00"), "USD", "wallet");
        cashOuts.saveAndFlush(first);
        first.markPaid("ops-1", "MANUAL", "BANK-REF-1");
        cashOuts.saveAndFlush(first);

        assertThatCode(() -> cashOuts.saveAndFlush(
                new RiderCashOut("rider-7", new BigDecimal("5.00"), "USD", "wallet")))
                .doesNotThrowAnyException();
    }

    @Test
    void the_balance_counts_only_what_the_platform_owes() {
        // The filter is in the query rather than in the caller, so an in-memory total and a
        // database total cannot answer differently. A company's rider and a cash tip are both
        // earnings and neither is a balance.
        String rider = "rider-8";
        ledger.saveAndFlush(job(rider, UUID.randomUUID()));
        ledger.saveAndFlush(RiderLedgerEntry.jobEarning(rider, UUID.randomUUID(),
                new BigDecimal("9.99"), "USD", RiderLedgerEntry.Fleet.CARRIER, "carrier-9",
                "customer-1", Instant.now()));
        ledger.saveAndFlush(RiderLedgerEntry.tip(rider, UUID.randomUUID(),
                new BigDecimal("5.00"), "USD", RiderLedgerEntry.Fleet.PLATFORM, null, true,
                Instant.now()));

        assertThat(ledger.balanceOf(rider)).isEqualByComparingTo("2.25");
    }
}
