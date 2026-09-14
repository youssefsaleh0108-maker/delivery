package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
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

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatEntry.HolderKind;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.RiderLedgerRepository;

/**
 * A shop's till, as the Back Office sees it and settles it (V52).
 *
 * <p>A pickup is paid at the counter of the shop that did the work, so the shop holds the platform's
 * cash until it pays it in. Paying in is nothing new: it is the remittance every holder makes, with
 * the safeguards a delivery company's payment brought — the amount the operator counted, a refusal
 * when the till moved, a request key that makes a double press harmless, and the operator's name on
 * the row. What is pinned here is that each of those holds for a shop, and that the Back Office's
 * list flags a shop's till by a line of its own rather than a rider's.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("a shop's till")
class MerchantCashTest {

    private static final String SHOP = "merchant-sub-1";
    private static final Instant NOW = Instant.parse("2026-10-24T12:00:00Z");

    @Mock
    private CashFloatRepository floats;
    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private BankPostingPublisher postings;
    @Mock
    private RiderLedgerRepository riderLedger;
    @Mock
    private AccountDirectory accounts;

    /** A row of the cash-on-hand query, shaped as Spring Data projects it. */
    private record Balance(String getHolderRef, HolderKind getHolderKind, BigDecimal getAmount,
                           long getOrders, Instant getOldest)
            implements CashFloatRepository.HolderBalance {
    }

    @Nested
    @DisplayName("on the Back Office's cash-on-hand list")
    class OnTheList {

        private CarrierCashService service;

        /**
         * Carrier line two days, platform line one, shop line three. Built here rather than in a
         * field initialiser: the mocks it takes do not exist until the extension creates them, after
         * this nested instance is constructed.
         */
        @BeforeEach
        void wire() {
            service = new CarrierCashService(floats, riderLedger, accounts, 48, 24, 72, "UTC",
                    "USD", Clock.fixed(NOW, ZoneOffset.UTC));
        }

        private CarrierCashService.OnHand listedWith(int hoursOld) {
            when(floats.outstandingByHolder()).thenReturn(List.of(new Balance(SHOP,
                    HolderKind.MERCHANT, new BigDecimal("52.50"), 2,
                    NOW.minus(Duration.ofHours(hoursOld)))));
            List<CarrierCashService.OnHand> list = service.cashOnHand();
            assertThat(list).hasSize(1);
            return list.get(0);
        }

        @Test
        @DisplayName("is listed as a shop, and flagged by the shop line alone")
        void flaggedByItsOwnLine() {
            CarrierCashService.OnHand line = listedWith(30);
            assertThat(line.holderKind()).isEqualTo(HolderKind.MERCHANT);
            assertThat(line.orders()).isEqualTo(2);
            // Late by a rider's day and by a company's two, and neither is a shop's rule.
            assertThat(line.overdue()).isFalse();
            assertThat(listedWith(50).overdue()).isFalse();
            assertThat(listedWith(73).overdue()).isTrue();
        }

        @Test
        @DisplayName("is never counted as a delivery company's cash")
        void notACompany() {
            when(floats.outstandingByHolder()).thenReturn(List.of(new Balance(SHOP,
                    HolderKind.MERCHANT, new BigDecimal("52.50"), 2, NOW)));

            assertThat(service.carriers()).isEmpty();
        }
    }

    @Nested
    @DisplayName("paid in to the platform")
    class PaidIn {

        private static final CashFloatEntry.Recorded BY_THE_OPERATOR = new CashFloatEntry.Recorded(
                "op-1", CashFloatEntry.Method.CASH, "counted at the shop", "till-key-0001");

        private CashFloatService cashFloat;

        @BeforeEach
        void wire() {
            cashFloat = new CashFloatService(floats, transactions, postings, "ACC-PLATFORM", "USD");
            // save() returns what it is given, as a real repository does for a new row.
            lenient().when(floats.save(any(CashFloatEntry.class))).thenAnswer(i -> i.getArgument(0));
            lenient().when(transactions.save(any(AccountingTransaction.class)))
                    .thenAnswer(i -> i.getArgument(0));
        }

        /** The till: one collection per pickup paid at the counter, oldest first. */
        private List<CashFloatEntry> tillHolds(String... amounts) {
            List<CashFloatEntry> rows = Arrays.stream(amounts)
                    .map(amount -> CashFloatEntry.collected(SHOP, HolderKind.MERCHANT,
                            UUID.randomUUID(), new BigDecimal(amount), "USD"))
                    .toList();
            when(floats.outstandingFor(SHOP)).thenReturn(rows);
            return rows;
        }

        @Test
        @DisplayName("records the counted till as the shop's payment, by the operator, and clears it")
        void recordsTheCountedTill() {
            List<CashFloatEntry> till = tillHolds("40.00", "12.50");

            CashFloatService.Remittance paid = cashFloat.remit(SHOP, "corr-1",
                    new BigDecimal("52.50"), BY_THE_OPERATOR).orElseThrow();

            assertThat(paid.amount()).isEqualByComparingTo("52.50");
            assertThat(paid.collections()).isEqualTo(2);
            assertThat(till).allSatisfy(row -> assertThat(row.getClearedBy()).isEqualTo(paid.id()));

            ArgumentCaptor<CashFloatEntry> row = ArgumentCaptor.forClass(CashFloatEntry.class);
            verify(floats).save(row.capture());
            assertThat(row.getValue().getEntryKind()).isEqualTo(CashFloatEntry.Kind.REMITTED);
            assertThat(row.getValue().getHolderKind()).isEqualTo(HolderKind.MERCHANT);
            assertThat(row.getValue().getHolderRef()).isEqualTo(SHOP);
            assertThat(row.getValue().getRecordedBy()).isEqualTo("op-1");
            assertThat(row.getValue().getMethod()).isEqualTo(CashFloatEntry.Method.CASH);
            assertThat(row.getValue().getRequestKey()).isEqualTo("till-key-0001");

            // Cash that reached the platform, posted once, as every holder's payment is.
            ArgumentCaptor<AccountingTransaction> posting =
                    ArgumentCaptor.forClass(AccountingTransaction.class);
            verify(transactions).save(posting.capture());
            assertThat(posting.getValue().getLeg())
                    .isEqualTo(AccountingTransaction.Leg.CASH_REMITTANCE);
            assertThat(posting.getValue().getAmount()).isEqualByComparingTo("52.50");
        }

        @Test
        @DisplayName("records nothing when the till holds more than the operator counted")
        void refusesATillThatMoved() {
            // A second pickup was paid at the counter after the operator's page loaded.
            List<CashFloatEntry> till = tillHolds("40.00", "12.50");

            assertThatThrownBy(() -> cashFloat.remit(SHOP, "corr-1", new BigDecimal("40.00"),
                    BY_THE_OPERATOR))
                    .isInstanceOfSatisfying(CashFloatService.AmountChangedException.class,
                            e -> assertThat(e.current()).isEqualByComparingTo("52.50"));
            assertThat(till).allMatch(CashFloatEntry::isOutstanding);
            verify(floats, never()).save(any());
            verify(transactions, never()).save(any());
            verifyNoInteractions(postings);
        }

        @Test
        @DisplayName("answers a repeated press with the first payment, and records no second")
        void aRepeatedPressReplays() {
            CashFloatEntry first = CashFloatEntry.remitted(SHOP, HolderKind.MERCHANT,
                    new BigDecimal("52.50"), "USD", BY_THE_OPERATOR);
            when(floats.findByRequestKey("till-key-0001")).thenReturn(Optional.of(first));
            when(floats.countClearedBy(List.of(first.getId())))
                    .thenReturn(List.<Object[]>of(new Object[] {first.getId(), 2L}));

            CashFloatService.Remittance again = cashFloat.remit(SHOP, "corr-2",
                    new BigDecimal("52.50"), BY_THE_OPERATOR).orElseThrow();

            assertThat(again.replayed()).isTrue();
            assertThat(again.id()).isEqualTo(first.getId());
            assertThat(again.collections()).isEqualTo(2);
            verify(floats, never()).outstandingFor(any());
            verify(floats, never()).save(any());
            verify(transactions, never()).save(any());
            verifyNoInteractions(postings);
        }

        @Test
        @DisplayName("refuses a key that already paid in somebody else's cash")
        void aKeyFromAnotherHolderIsRefused() {
            CashFloatEntry ridersPayment = CashFloatEntry.remitted("rider-1", HolderKind.RIDER,
                    new BigDecimal("13.25"), "USD", BY_THE_OPERATOR);
            when(floats.findByRequestKey("till-key-0001")).thenReturn(Optional.of(ridersPayment));

            assertThatThrownBy(() -> cashFloat.remit(SHOP, "corr-1", new BigDecimal("52.50"),
                    BY_THE_OPERATOR))
                    .isInstanceOf(CashFloatService.RequestKeyReusedException.class);
            verify(floats, never()).save(any());
            verifyNoInteractions(postings);
        }
    }
}
