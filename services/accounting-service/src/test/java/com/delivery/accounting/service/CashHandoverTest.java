package com.delivery.accounting.service;

import java.lang.reflect.Method;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyIterable;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.jpa.repository.Lock;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatEntry.HolderKind;
import com.delivery.accounting.domain.CashFloatEntry.Recorded;
import com.delivery.accounting.domain.CashFloatRepository;

import jakarta.persistence.LockModeType;

/**
 * A delivery company's rider handing their cash to the company, and the company paying the platform.
 *
 * <p>The property this file exists for: <strong>a hand-over moves custody and moves nothing
 * else.</strong> What the rider stops owing, the company starts owing — same orders, same cents —
 * and no bank posting is written, because no money reached the platform. The platform's posting
 * happens once, when the company pays. Get that wrong in one direction and a rider is chased for
 * cash that is in the hub's safe; in the other and the platform books takings it never received.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("cash hand-overs")
class CashHandoverTest {

    private static final String PLATFORM = "ACC-PLATFORM";
    private static final String RIDER = "rider-sub-1";
    private static final String COMPANY = "provider-77";
    private static final String STAFF = "carrier-staff-sub";
    private static final String KEY = "key-0000-1111";

    @Mock
    private CashFloatRepository floatEntries;
    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private BankPostingPublisher postings;

    private CashFloatService service;

    @BeforeEach
    void setUp() {
        service = new CashFloatService(floatEntries, transactions, postings, PLATFORM, "USD");
        lenient().when(floatEntries.save(any(CashFloatEntry.class))).thenAnswer(i -> i.getArgument(0));
        lenient().when(floatEntries.saveAll(anyIterable())).thenAnswer(i -> i.getArgument(0));
        lenient().when(transactions.save(any(AccountingTransaction.class)))
                .thenAnswer(i -> i.getArgument(0));
    }

    private static CashFloatEntry collectedForCompany(String amount) {
        return CashFloatEntry.collected(RIDER, HolderKind.RIDER, UUID.randomUUID(),
                new BigDecimal(amount), "USD", COMPANY);
    }

    private List<CashFloatEntry> riderHolds(String... amounts) {
        List<CashFloatEntry> rows = new ArrayList<>();
        for (String amount : amounts) {
            rows.add(collectedForCompany(amount));
        }
        when(floatEntries.lockHeldForCarrier(RIDER, COMPANY)).thenReturn(rows);
        return rows;
    }

    private static Recorded byStaff(String key) {
        return new Recorded(STAFF, CashFloatEntry.Method.CASH, "counted at the Hamra hub", key);
    }

    @SuppressWarnings("unchecked")
    private List<CashFloatEntry> custodyWritten() {
        ArgumentCaptor<Iterable<CashFloatEntry>> saved = ArgumentCaptor.forClass(Iterable.class);
        verify(floatEntries).saveAll(saved.capture());
        List<CashFloatEntry> out = new ArrayList<>();
        saved.getValue().forEach(out::add);
        return out;
    }

    private CashFloatEntry transferWritten() {
        ArgumentCaptor<CashFloatEntry> saved = ArgumentCaptor.forClass(CashFloatEntry.class);
        verify(floatEntries).save(saved.capture());
        return saved.getValue();
    }

    @Nested
    @DisplayName("a rider handing cash to their company")
    class HandingOver {

        @Test
        @DisplayName("clears every row it covers, by the transfer that covered it")
        void clearsTheRidersRows() {
            List<CashFloatEntry> held = riderHolds("145.00", "120.00", "220.00");

            CashFloatService.Handover handover =
                    service.handOver(COMPANY, RIDER, new BigDecimal("485.00"), byStaff(KEY));

            assertThat(handover.amount()).isEqualByComparingTo("485.00");
            assertThat(handover.collections()).isEqualTo(3);
            assertThat(handover.replayed()).isFalse();
            assertThat(held).allMatch(row -> !row.isOutstanding());
            assertThat(held).allMatch(row -> handover.id().equals(row.getClearedBy()));
        }

        @Test
        @DisplayName("gives the company exactly the orders and cents the rider stopped holding")
        void custodyBalances() {
            List<CashFloatEntry> held = riderHolds("145.00", "120.00", "220.00");

            CashFloatService.Handover handover =
                    service.handOver(COMPANY, RIDER, new BigDecimal("485.00"), byStaff(KEY));

            List<CashFloatEntry> custody = custodyWritten();
            assertThat(custody).hasSize(3);
            // Same orders, same amounts, one to one — custody moved and not a cent appeared.
            assertThat(custody).extracting(CashFloatEntry::getOrderId)
                    .containsExactlyElementsOf(held.stream().map(CashFloatEntry::getOrderId).toList());
            assertThat(custody).extracting(CashFloatEntry::getAmount)
                    .containsExactlyElementsOf(held.stream().map(CashFloatEntry::getAmount).toList());
            BigDecimal moved = custody.stream().map(CashFloatEntry::getAmount)
                    .reduce(BigDecimal.ZERO, BigDecimal::add);
            assertThat(moved).isEqualByComparingTo(handover.amount());
            // Held by the company now, outstanding, and traceable to the hand-over that moved it.
            assertThat(custody).allSatisfy(row -> {
                assertThat(row.getHolderRef()).isEqualTo(COMPANY);
                assertThat(row.getHolderKind()).isEqualTo(HolderKind.PROVIDER);
                assertThat(row.getCarrierRef()).isEqualTo(COMPANY);
                assertThat(row.isOutstanding()).isTrue();
                assertThat(row.isCustodyCopy()).isTrue();
                assertThat(row.getHandoverId()).isEqualTo(handover.id());
            });
        }

        @Test
        @DisplayName("records who took it, how, and the key that makes a double press harmless")
        void theTransferRowIsTheAuditTrail() {
            riderHolds("485.00");

            service.handOver(COMPANY, RIDER, new BigDecimal("485.00"), byStaff(KEY));

            CashFloatEntry transfer = transferWritten();
            assertThat(transfer.getEntryKind()).isEqualTo(CashFloatEntry.Kind.TRANSFERRED);
            assertThat(transfer.getHolderRef()).isEqualTo(RIDER);
            assertThat(transfer.getHolderKind()).isEqualTo(HolderKind.RIDER);
            assertThat(transfer.getCarrierRef()).isEqualTo(COMPANY);
            assertThat(transfer.getRecordedBy()).isEqualTo(STAFF);
            assertThat(transfer.getMethod()).isEqualTo(CashFloatEntry.Method.CASH);
            assertThat(transfer.getNote()).isEqualTo("counted at the Hamra hub");
            assertThat(transfer.getRequestKey()).isEqualTo(KEY);
            assertThat(transfer.getOrderId()).isNull();
        }

        /**
         * No money reached the platform, so the platform's books are not touched. The company's
         * payment is where the one CASH_REMITTANCE for this cash will be written.
         */
        @Test
        @DisplayName("posts nothing: no money reached the platform")
        void noPosting() {
            riderHolds("485.00");

            service.handOver(COMPANY, RIDER, new BigDecimal("485.00"), byStaff(KEY));

            verifyNoInteractions(transactions, postings);
        }

        @Test
        @DisplayName("refuses an amount that is not what the rider holds, and records nothing")
        void staleAmountIsRefused() {
            // The page loaded at 485.00; the rider collected another 30.00 since.
            riderHolds("485.00", "30.00");

            assertThatThrownBy(() -> service.handOver(COMPANY, RIDER, new BigDecimal("485.00"),
                    byStaff(KEY)))
                    .isInstanceOf(CashFloatService.AmountChangedException.class)
                    .satisfies(e -> assertThat(
                            ((CashFloatService.AmountChangedException) e).current())
                            .isEqualByComparingTo("515.00"));

            verify(floatEntries, never()).save(any());
            verify(floatEntries, never()).saveAll(anyIterable());
        }

        /**
         * The second press of a button with no key: the first cleared the rows under the lock, so
         * the second finds nothing and is refused rather than recorded.
         */
        @Test
        @DisplayName("a second press after the first cleared everything is refused, not recorded")
        void secondPressFindsNothing() {
            when(floatEntries.lockHeldForCarrier(RIDER, COMPANY)).thenReturn(List.of());

            assertThatThrownBy(() -> service.handOver(COMPANY, RIDER, new BigDecimal("485.00"),
                    byStaff(null)))
                    .isInstanceOf(CashFloatService.AmountChangedException.class);
            verify(floatEntries, never()).save(any());
        }

        @Test
        @DisplayName("a repeated key answers with the first hand-over and writes nothing")
        void repeatedKeyReplays() {
            CashFloatEntry first = CashFloatEntry.transferred(RIDER, COMPANY,
                    new BigDecimal("485.00"), "USD", byStaff(KEY));
            when(floatEntries.findByRequestKey(KEY)).thenReturn(Optional.of(first));
            when(floatEntries.countClearedBy(List.of(first.getId())))
                    .thenReturn(List.<Object[]>of(new Object[] {first.getId(), 3L}));

            CashFloatService.Handover again =
                    service.handOver(COMPANY, RIDER, new BigDecimal("485.00"), byStaff(KEY));

            assertThat(again.replayed()).isTrue();
            assertThat(again.id()).isEqualTo(first.getId());
            assertThat(again.collections()).isEqualTo(3);
            // Never even locked the rows, let alone cleared them again.
            verify(floatEntries, never()).lockHeldForCarrier(anyString(), anyString());
            verify(floatEntries, never()).save(any());
        }

        /**
         * Two presses racing: the second waited on the first's row locks, and by the time it has
         * them the first has committed under the same key. It must answer with that, not refuse.
         */
        @Test
        @DisplayName("a twin that committed while this one waited on the lock is replayed")
        void twinCommittedDuringTheWait() {
            CashFloatEntry first = CashFloatEntry.transferred(RIDER, COMPANY,
                    new BigDecimal("485.00"), "USD", byStaff(KEY));
            when(floatEntries.findByRequestKey(KEY))
                    .thenReturn(Optional.empty())
                    .thenReturn(Optional.of(first));
            when(floatEntries.lockHeldForCarrier(RIDER, COMPANY)).thenReturn(List.of());
            when(floatEntries.countClearedBy(List.of(first.getId())))
                    .thenReturn(List.<Object[]>of(new Object[] {first.getId(), 1L}));

            CashFloatService.Handover again =
                    service.handOver(COMPANY, RIDER, new BigDecimal("485.00"), byStaff(KEY));

            assertThat(again.replayed()).isTrue();
            verify(floatEntries, never()).save(any());
        }

        @Test
        @DisplayName("a key already used for another rider is refused")
        void keyReusedForSomebodyElse() {
            CashFloatEntry other = CashFloatEntry.transferred("rider-sub-2", COMPANY,
                    new BigDecimal("10.00"), "USD", byStaff(KEY));
            when(floatEntries.findByRequestKey(KEY)).thenReturn(Optional.of(other));

            assertThatThrownBy(() -> service.handOver(COMPANY, RIDER, new BigDecimal("485.00"),
                    byStaff(KEY)))
                    .isInstanceOf(CashFloatService.RequestKeyReusedException.class);
            verify(floatEntries, never()).save(any());
        }

        /**
         * A pay run's deduction is replayed by its key, and the key can be worked out from the run
         * and the rider. A counter hand-over that took the key first must not be answered as the
         * deduction: the rider would hand the notes over and lose them from their pay as well.
         */
        @Test
        @DisplayName("a counter hand-over under a pay run's key is never replayed as that run's deduction")
        void aReplayRepeatsTheMethod() {
            String payrollKey = CarrierPayrollService.payrollKey(UUID.randomUUID(), RIDER);
            // Recorded before counters were refused the prefix, or by a path that forgot to be.
            CashFloatEntry counter = CashFloatEntry.transferred(RIDER, COMPANY,
                    new BigDecimal("485.00"), "USD",
                    new Recorded(STAFF, CashFloatEntry.Method.CASH, null, payrollKey));
            when(floatEntries.findByRequestKey(payrollKey)).thenReturn(Optional.of(counter));

            assertThatThrownBy(() -> service.handOver(COMPANY, RIDER, new BigDecimal("485.00"),
                    new Recorded(STAFF, CashFloatEntry.Method.PAYROLL_DEDUCTION,
                            "2026-10-01 to 2026-10-15", payrollKey)))
                    .isInstanceOf(CashFloatService.RequestKeyReusedException.class);

            // And any other change of method under a repeated key is a different request too.
            CashFloatEntry first = CashFloatEntry.transferred(RIDER, COMPANY,
                    new BigDecimal("485.00"), "USD", byStaff(KEY));
            when(floatEntries.findByRequestKey(KEY)).thenReturn(Optional.of(first));
            assertThatThrownBy(() -> service.handOver(COMPANY, RIDER, new BigDecimal("485.00"),
                    new Recorded(STAFF, CashFloatEntry.Method.WALLET, null, KEY)))
                    .isInstanceOf(CashFloatService.RequestKeyReusedException.class);

            verify(floatEntries, never()).lockHeldForCarrier(anyString(), anyString());
            verify(floatEntries, never()).save(any());
        }

        @Test
        @DisplayName("a pay run's key records nothing but a payroll deduction, and a deduction needs its key")
        void payrollKeysBelongToPayroll() {
            String payrollKey = CarrierPayrollService.payrollKey(UUID.randomUUID(), RIDER);
            for (Recorded wrong : List.of(
                    new Recorded(STAFF, CashFloatEntry.Method.CASH, null, payrollKey),
                    new Recorded(STAFF, CashFloatEntry.Method.CASH, null,
                            payrollKey.toUpperCase(Locale.ROOT)),
                    new Recorded(STAFF, CashFloatEntry.Method.PAYROLL_DEDUCTION, null, KEY),
                    new Recorded(STAFF, CashFloatEntry.Method.PAYROLL_DEDUCTION, null, null))) {
                assertThatThrownBy(() -> service.handOver(COMPANY, RIDER,
                        new BigDecimal("485.00"), wrong))
                        .as(String.valueOf(wrong))
                        .isInstanceOf(IllegalArgumentException.class);
            }
            verify(floatEntries, never()).findByRequestKey(anyString());
            verify(floatEntries, never()).lockHeldForCarrier(anyString(), anyString());
        }

        @Test
        @DisplayName("accepts a whole-cent amount written with extra zeros")
        void paddedAmountIsWholeCents() {
            riderHolds("485.00");

            CashFloatService.Handover handover =
                    service.handOver(COMPANY, RIDER, new BigDecimal("485.000"), byStaff(KEY));

            assertThat(handover.amount()).isEqualByComparingTo("485.00");
        }

        @Test
        @DisplayName("refuses nothing, a negative amount, or fractions of a cent")
        void nonsenseAmounts() {
            for (String amount : List.of("0.00", "-5.00", "10.001")) {
                assertThatThrownBy(() -> service.handOver(COMPANY, RIDER, new BigDecimal(amount),
                        byStaff(null)))
                        .as(amount)
                        .isInstanceOf(IllegalArgumentException.class);
            }
            verify(floatEntries, never()).lockHeldForCarrier(anyString(), anyString());
        }
    }

    @Nested
    @DisplayName("the company paying the platform")
    class Paying {

        private List<CashFloatEntry> companyHolds(String... amounts) {
            List<CashFloatEntry> rows = new ArrayList<>();
            UUID transfer = UUID.randomUUID();
            for (String amount : amounts) {
                rows.add(CashFloatEntry.custodyOf(COMPANY, UUID.randomUUID(),
                        new BigDecimal(amount), "USD", transfer));
            }
            when(floatEntries.outstandingFor(COMPANY)).thenReturn(rows);
            return rows;
        }

        @Test
        @DisplayName("clears its custody and posts the one CASH_REMITTANCE this cash will ever get")
        void remittancePostsOnce() {
            List<CashFloatEntry> held = companyHolds("145.00", "340.00");

            Optional<CashFloatService.Remittance> paid = service.remit(COMPANY, "corr-1",
                    new BigDecimal("485.00"),
                    new Recorded("op-1", CashFloatEntry.Method.BANK_DEPOSIT, null, null));

            assertThat(paid).isPresent();
            assertThat(paid.get().amount()).isEqualByComparingTo("485.00");
            assertThat(held).allMatch(row -> !row.isOutstanding());
            ArgumentCaptor<AccountingTransaction> posting =
                    ArgumentCaptor.forClass(AccountingTransaction.class);
            verify(transactions).save(posting.capture());
            assertThat(posting.getValue().getLeg())
                    .isEqualTo(AccountingTransaction.Leg.CASH_REMITTANCE);
            assertThat(posting.getValue().getAmount()).isEqualByComparingTo("485.00");
        }

        @Test
        @DisplayName("records the operator and how it was paid on the remittance row")
        void remittanceRecordsWho() {
            companyHolds("485.00");

            service.remit(COMPANY, "corr-1", new BigDecimal("485.00"),
                    new Recorded("op-1", CashFloatEntry.Method.BANK_DEPOSIT, "slip 4471", null));

            CashFloatEntry remittance = transferWritten();
            assertThat(remittance.getEntryKind()).isEqualTo(CashFloatEntry.Kind.REMITTED);
            assertThat(remittance.getHolderKind()).isEqualTo(HolderKind.PROVIDER);
            assertThat(remittance.getCarrierRef()).isEqualTo(COMPANY);
            assertThat(remittance.getRecordedBy()).isEqualTo("op-1");
            assertThat(remittance.getMethod()).isEqualTo(CashFloatEntry.Method.BANK_DEPOSIT);
            assertThat(remittance.getNote()).isEqualTo("slip 4471");
        }

        @Test
        @DisplayName("refuses an amount that moved since the operator looked, and posts nothing")
        void staleAmountIsRefused() {
            // Another rider handed over 40.00 at the hub while the operator was counting.
            companyHolds("485.00", "40.00");

            assertThatThrownBy(() -> service.remit(COMPANY, "corr-1", new BigDecimal("485.00"),
                    Recorded.nobody()))
                    .isInstanceOf(CashFloatService.AmountChangedException.class);

            verify(floatEntries, never()).save(any());
            verifyNoInteractions(transactions, postings);
        }

        @Test
        @DisplayName("a pay run's key never records a payment, and a repeated key must repeat the method")
        void remittanceKeys() {
            assertThatThrownBy(() -> service.remit(COMPANY, "corr-1", new BigDecimal("485.00"),
                    new Recorded("op-1", CashFloatEntry.Method.BANK_DEPOSIT, null,
                            CarrierPayrollService.payrollKey(UUID.randomUUID(), RIDER))))
                    .isInstanceOf(IllegalArgumentException.class);

            CashFloatEntry first = CashFloatEntry.remitted(COMPANY, HolderKind.PROVIDER,
                    new BigDecimal("485.00"), "USD",
                    new Recorded("op-1", CashFloatEntry.Method.BANK_DEPOSIT, null, KEY));
            when(floatEntries.findByRequestKey(KEY)).thenReturn(Optional.of(first));
            assertThatThrownBy(() -> service.remit(COMPANY, "corr-1", new BigDecimal("485.00"),
                    new Recorded("op-1", CashFloatEntry.Method.CASH, null, KEY)))
                    .isInstanceOf(CashFloatService.RequestKeyReusedException.class);

            verify(floatEntries, never()).outstandingFor(anyString());
            verify(floatEntries, never()).save(any());
            verifyNoInteractions(transactions, postings);
        }

        @Test
        @DisplayName("without an expected amount it banks everything, exactly as before")
        void theOldCallStillWorks() {
            companyHolds("485.00", "40.00");

            assertThat(service.remitAll(COMPANY, "corr-1").orElseThrow().amount())
                    .isEqualByComparingTo("525.00");
        }
    }

    /**
     * The lock is what makes two simultaneous presses record one remittance and one hand-over.
     * It cannot be exercised without a database, so the annotation that asks for it is pinned: a
     * refactor that drops it fails here rather than in a double-booked bank posting.
     */
    @Test
    @DisplayName("the rows a remittance or a hand-over clears are read under a write lock")
    void clearingReadsAreLocked() throws Exception {
        for (Method method : List.of(
                CashFloatRepository.class.getMethod("outstandingFor", String.class),
                CashFloatRepository.class.getMethod("lockHeldForCarrier",
                        String.class, String.class))) {
            Lock lock = method.getAnnotation(Lock.class);
            assertThat(lock).as(method.getName()).isNotNull();
            assertThat(lock.value()).isEqualTo(LockModeType.PESSIMISTIC_WRITE);
        }
        // And the page reads are NOT locked: Postgres refuses FOR UPDATE in a read-only transaction.
        for (Method method : List.of(
                CashFloatRepository.class.getMethod("heldBy", String.class),
                CashFloatRepository.class.getMethod("heldForCarrier", String.class, String.class),
                CashFloatRepository.class.getMethod("heldByRidersFor", String.class))) {
            assertThat(method.getAnnotation(Lock.class)).as(method.getName()).isNull();
        }
    }
}
