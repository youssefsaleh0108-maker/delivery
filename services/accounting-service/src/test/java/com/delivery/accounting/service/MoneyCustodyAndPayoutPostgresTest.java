package com.delivery.accounting.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.PointsEntry.OwnerKind;
import com.delivery.accounting.domain.PointsEntryRepository;
import com.delivery.accounting.domain.PointsRedemption;
import com.delivery.accounting.domain.RiderCashOut;
import com.delivery.accounting.domain.RiderLedgerEntry;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.payout.ManualPayoutProvider;
import com.delivery.accounting.payout.RiderPayoutProviders;

/**
 * Cash custody and payouts against a real Postgres, with real transactions (reconciliation deep
 * test). Every test fails today and names its finding.
 *
 * <ul>
 *   <li><b>RECON-03</b>: the Back Office's "banked" on a rider clears cash the rider owes their
 *       delivery company.</li>
 *   <li><b>RECON-07</b>: two people deciding the same cash-out or redemption at once both win:
 *       money is paid and handed back to the balance too.</li>
 *   <li><b>RECON-12</b>: a rider's cash-out is netted against cash they owe their company.</li>
 * </ul>
 *
 * <p>Self-migrating (Flyway on), so it needs only an empty database with an {@code accounting}
 * schema, and skipped unless one is there:
 *
 * <pre>
 * docker run --rm -d --name acct-pg -p 55533:5432 -e POSTGRES_PASSWORD=test -e POSTGRES_DB=accounting postgis/postgis:17-3.5
 * docker exec acct-pg psql -U postgres -d accounting -c "create schema accounting"
 * mvn -o -pl services/accounting-service -am test -Dtest=MoneyCustodyAndPayoutPostgresTest \
 *     -Dsurefire.failIfNoSpecifiedTests=false -Ddelivery.test.postgres=true \
 *     -Ddelivery.test.postgres.url=jdbc:postgresql://localhost:55533/accounting
 * </pre>
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@TestPropertySource(properties = {
        "spring.datasource.url=${delivery.test.postgres.url:jdbc:postgresql://localhost:55433/accounting}",
        "spring.datasource.username=postgres",
        "spring.datasource.password=test",
        "spring.flyway.enabled=true",
        "spring.jpa.hibernate.ddl-auto=validate"
})
@Import({CashFloatService.class, RiderEarningsService.class, PointsService.class,
        RiderPayoutProviders.class, ManualPayoutProvider.class})
@EnabledIfSystemProperty(named = "delivery.test.postgres", matches = "true")
// Real commits: the races below are between transactions, and a rolled-back test proves nothing.
@Transactional(propagation = Propagation.NOT_SUPPORTED)
@DisplayName("cash custody and payouts, against Postgres (reconciliation deep test)")
class MoneyCustodyAndPayoutPostgresTest {

    private static final CashFloatEntry.HolderKind RIDER = CashFloatEntry.HolderKind.RIDER;

    @MockitoBean
    private BankPostingPublisher postings;

    @Autowired
    private CashFloatService cashFloat;
    @Autowired
    private RiderEarningsService riderEarnings;
    @Autowired
    private PointsService points;
    @Autowired
    private CashFloatRepository floats;
    @Autowired
    private RiderLedgerRepository riderLedger;
    @Autowired
    private PointsEntryRepository pointsLedger;
    @Autowired
    private PlatformTransactionManager transactionManager;

    private static String unique(String prefix) {
        return prefix + "-" + UUID.randomUUID();
    }

    private static BigDecimal money(String amount) {
        return new BigDecimal(amount);
    }

    // ------------------------------------------------------------------------------ RECON-03

    @Test
    @DisplayName("RECON-03: banking a rider's own-fleet takings leaves the cash they owe their company")
    void bankingARiderLeavesTheirCompanysCash() {
        // The dev rider in the deep test: 254.87 of platform-fleet cash and 76.39 collected on jobs
        // for delivery company 5857ac51, which the owner's rule says the rider owes the company.
        String rider = unique("rider");
        String company = unique("carrier");
        floats.saveAndFlush(CashFloatEntry.collected(rider, RIDER, UUID.randomUUID(),
                money("254.87"), "USD", null));
        floats.saveAndFlush(CashFloatEntry.collected(rider, RIDER, UUID.randomUUID(),
                money("76.39"), "USD", company));

        // The Back Office list shows ONE line for the rider, and its "Yes, they banked it" sends the
        // holder kind and nothing else (reconciliation_screen.dart _remit): no amount, no key.
        assertThat(floats.outstandingByHolder())
                .filteredOn(row -> row.getHolderRef().equals(rider))
                .singleElement()
                .satisfies(row -> assertThat(row.getAmount()).isEqualByComparingTo("331.26"));
        cashFloat.remit(rider, "corr", null,
                new CashFloatEntry.Recorded("backoffice-1", null, null, null), RIDER);

        // The company's cash is still the company's to take in, and the company can record it.
        assertThat(floats.heldForCarrier(rider, company))
                .as("cash the rider still owes their delivery company")
                .extracting(CashFloatEntry::getAmount)
                .usingElementComparator(BigDecimal::compareTo)
                .containsExactly(money("76.39"));
        assertThatCode(() -> cashFloat.handOver(company, rider, money("76.39"),
                new CashFloatEntry.Recorded("carrier-staff-1", CashFloatEntry.Method.CASH, null,
                        "recon-handover-" + UUID.randomUUID().toString().substring(0, 8))))
                .as("the company recording its rider's hand-over afterwards")
                .doesNotThrowAnyException();
    }

    // ------------------------------------------------------------------------------ RECON-12

    @Test
    @DisplayName("RECON-12: what a rider may cash out is not netted against their company's cash")
    void availableIgnoresCashOwedToTheCompany() {
        String rider = unique("rider");
        String company = unique("carrier");
        // The platform owes the rider 20.00 for own-fleet work...
        riderLedger.saveAndFlush(RiderLedgerEntry.jobEarning(rider, UUID.randomUUID(),
                money("20.00"), "USD", RiderLedgerEntry.Fleet.PLATFORM, null, "customer-1",
                Instant.now()));
        // ...and they hold 30.00 collected on jobs for their company, which the company nets in
        // its own payroll (PayslipCalculator) or takes at its hub.
        floats.saveAndFlush(CashFloatEntry.collected(rider, RIDER, UUID.randomUUID(),
                money("30.00"), "USD", company));

        assertThat(riderEarnings.availableFor(rider))
                .as("available to cash out: owed by the platform, less cash owed to the platform")
                .isEqualByComparingTo("20.00");
    }

    // ------------------------------------------------------------------------------ RECON-07

    /**
     * Runs {@code first} in a transaction that stays open, uncommitted, while {@code second} runs
     * and commits in its own; then commits the first. Neither service takes a lock or checks a
     * version, so the first transaction's write is deferred to its commit and nothing blocks.
     */
    private void interleave(Runnable first, Runnable second) throws Exception {
        CountDownLatch firstRead = new CountDownLatch(1);
        CountDownLatch secondDone = new CountDownLatch(1);
        AtomicReference<Throwable> failure = new AtomicReference<>();
        Thread thread = new Thread(() -> {
            try {
                new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
                    first.run();
                    firstRead.countDown();
                    try {
                        secondDone.await(30, TimeUnit.SECONDS);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                    }
                });
            } catch (Throwable t) {
                failure.set(t);
            } finally {
                firstRead.countDown();
            }
        });
        thread.start();
        assertThat(firstRead.await(30, TimeUnit.SECONDS)).isTrue();
        try {
            second.run();
        } finally {
            secondDone.countDown();
            thread.join(30_000);
        }
        // Whichever of the two refused is fine; both succeeding is the bug.
        if (failure.get() != null) {
            System.out.println("first decision refused: " + failure.get());
        }
    }

    @Test
    @DisplayName("RECON-07: a cash-out paid and refused at the same moment is not paid twice")
    void aCashOutPaidAndRefusedAtOnce() throws Exception {
        String rider = unique("rider");
        riderLedger.saveAndFlush(RiderLedgerEntry.jobEarning(rider, UUID.randomUUID(),
                money("50.00"), "USD", RiderLedgerEntry.Fleet.PLATFORM, null, "customer-1",
                Instant.now()));
        RiderCashOut request = riderEarnings.requestCashOut(rider, money("40.00"), "wallet 123");
        UUID id = request.getId();

        // Two operators on the same queue row: one refuses it, one pays it by hand.
        interleave(
                () -> riderEarnings.rejectCashOut(id, "operator-2", "looks like a duplicate"),
                () -> riderEarnings.payCashOut(id, "operator-1", "BANK-REF-0919"));

        boolean paid = riderLedger.findAll().stream().anyMatch(e -> rider.equals(e.getRiderRef())
                && e.getEntryType() == RiderLedgerEntry.EntryType.CASHOUT_PAID);
        boolean released = riderLedger.findAll().stream().anyMatch(e -> rider.equals(e.getRiderRef())
                && e.getEntryType() == RiderLedgerEntry.EntryType.CASHOUT_RELEASED);
        assertThat(paid && released)
                .as("the cash-out was both paid (BANK-REF-0919) and released back to the balance")
                .isFalse();
        // If the money went out, only 10.00 is left to take out; the balance must say so.
        if (paid) {
            assertThat(riderEarnings.balanceOf(rider)).isEqualByComparingTo("10.00");
        }
    }

    @Test
    @DisplayName("RECON-07: a redemption refused by the Back Office as its owner cancels it is released once")
    void aRedemptionRefusedAndCancelledAtOnce() throws Exception {
        String shop = unique("merchant");
        // 1,000.00 of goods at 5 points a dollar: 5,000 points.
        points.awardForDelivery(UUID.randomUUID(), shop, money("1000.00"), null, null, null,
                null, null);
        PointsRedemption request = points.request(OwnerKind.MERCHANT, shop, 1000, "IBAN ...", shop);

        interleave(
                () -> points.reject(request.getId(), "operator-1", "wrong IBAN"),
                () -> points.cancel(request.getId(), shop));

        assertThat(pointsLedger.balanceOf(OwnerKind.MERCHANT, shop))
                .as("5,000 earned, 1,000 held, released once")
                .isEqualTo(5000L);
    }

    @Test
    @DisplayName("RECON-07: a redemption approved as its owner cancels it cannot be paid out as well")
    void aRedemptionApprovedWhileCancelledIsNotAlsoPaid() throws Exception {
        String shop = unique("merchant");
        points.awardForDelivery(UUID.randomUUID(), shop, money("1000.00"), null, null, null,
                null, null);
        PointsRedemption request = points.request(OwnerKind.MERCHANT, shop, 1000, "IBAN ...", shop);

        interleave(
                () -> points.approve(request.getId(), "operator-1", "ok"),
                () -> points.cancel(request.getId(), shop));

        // What the operator sees next: if the request still reads APPROVED, they pay it by hand.
        boolean payable = points.find(request.getId())
                .map(r -> r.getStatus() == PointsRedemption.Status.APPROVED)
                .orElse(false);
        if (payable) {
            points.markPaid(request.getId(), "operator-1", "BANK-REF-0919");
        }
        long balance = pointsLedger.balanceOf(OwnerKind.MERCHANT, shop);
        assertThat(payable && balance == 5000L)
                .as("10.00 paid out for 1,000 points that are back in the balance (" + balance + ")")
                .isFalse();
    }
}
