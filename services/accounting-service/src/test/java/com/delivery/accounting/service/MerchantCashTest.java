package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.Mockito.atLeastOnce;
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
 * <p>A pickup is paid in full at the counter of the shop that did the work. The shop keeps its own
 * share of that cash and pays the platform only the platform's part, its commission, so paying in is
 * a remittance on terms of its own: cleared against what the shop owes and never against the till,
 * with the share it kept recorded beside the payment and posted nowhere. The safeguards a delivery
 * company's payment brought all hold — the amount the operator confirmed, a refusal when the till
 * moved, a request key that makes a double press harmless, the operator's name on the row — and an
 * account that is a shop and a rider at once never has its till and its bag paid in as one.
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

    /** A row of the per-holder query the companies' list reads, shaped as Spring Data projects it. */
    private record Balance(String getHolderRef, HolderKind getHolderKind, BigDecimal getAmount,
                           long getOrders, Instant getOldest)
            implements CashFloatRepository.HolderBalance {
    }

    /** A row of the cash-on-hand query: a shop's till is owed to the platform, so no company. */
    private record Line(String getHolderRef, HolderKind getHolderKind, String getCarrierRef,
                        BigDecimal getAmount, long getOrders, Instant getOldest)
            implements CashFloatRepository.CreditorBalance {
    }

    private CashFloatService cashFloat() {
        return cashFloat(SettlementService.SettlementMode.LEDGER_ONLY);
    }

    private CashFloatService cashFloat(SettlementService.SettlementMode mode) {
        CashFloatService service = new CashFloatService(floats, transactions, postings,
                "ACC-PLATFORM", "USD", mode);
        // save() returns what it is given, as a real repository does for a new row.
        lenient().when(floats.save(any(CashFloatEntry.class))).thenAnswer(i -> i.getArgument(0));
        lenient().when(transactions.save(any(AccountingTransaction.class)))
                .thenAnswer(i -> i.getArgument(0));
        return service;
    }

    /** Every float row a call wrote, in order. */
    private List<CashFloatEntry> written() {
        ArgumentCaptor<CashFloatEntry> rows = ArgumentCaptor.forClass(CashFloatEntry.class);
        verify(floats, atLeastOnce()).save(rows.capture());
        return rows.getAllValues();
    }

    private static CashFloatEntry only(List<CashFloatEntry> rows, CashFloatEntry.Kind kind) {
        List<CashFloatEntry> matching =
                rows.stream().filter(row -> row.getEntryKind() == kind).toList();
        assertThat(matching).as(kind + " rows").hasSize(1);
        return matching.get(0);
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
            when(floats.outstandingByCreditor()).thenReturn(List.of(new Line(SHOP,
                    HolderKind.MERCHANT, null, new BigDecimal("52.50"), 2,
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

        @Test
        @DisplayName("says what each shop owes out of its till: the commission, not the till")
        void saysWhatEachShopOwes() {
            List<AccountingTransaction> legs = new ArrayList<>();
            UUID printing = UUID.randomUUID();
            UUID copies = UUID.randomUUID();
            legs.add(Legs.merchantCredit(printing, "35.00", SHOP));
            legs.add(Legs.commission(printing, "5.00"));
            legs.add(Legs.merchantCredit(copies, "10.94", "merchant-sub-2"));
            legs.add(Legs.commission(copies, "1.56"));
            when(floats.heldByKind(HolderKind.MERCHANT)).thenReturn(List.of(
                    CashFloatEntry.collected(SHOP, HolderKind.MERCHANT, printing,
                            new BigDecimal("40.00"), "USD"),
                    CashFloatEntry.collected("merchant-sub-2", HolderKind.MERCHANT, copies,
                            new BigDecimal("12.50"), "USD")));
            when(transactions.findByOrderIdIn(anyCollection())).thenReturn(legs);

            var tills = cashFloat().shopTills();

            assertThat(tills.get(SHOP).held()).isEqualByComparingTo("40.00");
            assertThat(tills.get(SHOP).owed()).isEqualByComparingTo("5.00");
            assertThat(tills.get(SHOP).retained()).isEqualByComparingTo("35.00");
            assertThat(tills.get("merchant-sub-2").owed()).isEqualByComparingTo("1.56");
        }
    }

    @Nested
    @DisplayName("paid in to the platform")
    class PaidIn {

        private static final CashFloatEntry.Recorded BY_THE_OPERATOR = new CashFloatEntry.Recorded(
                "op-1", CashFloatEntry.Method.CASH, "counted at the shop", "till-key-0001");

        private CashFloatService cashFloat;

        /** Every leg on the till's orders, as settlement wrote them. */
        private final List<AccountingTransaction> legs = new ArrayList<>();

        @BeforeEach
        void wire() {
            cashFloat = cashFloat();
            lenient().when(transactions.findByOrderIdIn(anyCollection())).thenReturn(legs);
        }

        /** One pickup paid at the counter: its cash in the till, and its legs on the ledger. */
        private CashFloatEntry pickup(String cash, String share, String commission) {
            UUID order = UUID.randomUUID();
            legs.add(Legs.cashHeldByShop(order, cash, SHOP));
            legs.add(Legs.merchantCredit(order, share, SHOP));
            legs.add(Legs.commission(order, commission));
            return CashFloatEntry.collected(SHOP, HolderKind.MERCHANT, order, new BigDecimal(cash),
                    "USD");
        }

        /** The till as the remittance locks it: the shop's collections, oldest first. */
        private List<CashFloatEntry> tillHolds(CashFloatEntry... rows) {
            List<CashFloatEntry> till = List.of(rows);
            when(floats.outstandingFor(SHOP, HolderKind.MERCHANT)).thenReturn(till);
            return till;
        }

        private void nothingRecorded(List<CashFloatEntry> till) {
            assertThat(till).allMatch(CashFloatEntry::isOutstanding);
            verify(floats, never()).save(any());
            verify(transactions, never()).save(any());
            verifyNoInteractions(postings);
        }

        @Test
        @DisplayName("on one pickup, takes the commission, records the share the shop kept, and "
                + "clears the till")
        void onePickup() {
            // 40.00 of printing at 12.5%: 35.00 is the shop's, 5.00 the platform's.
            List<CashFloatEntry> till = tillHolds(pickup("40.00", "35.00", "5.00"));

            CashFloatService.Remittance paid = cashFloat.remit(SHOP, "corr-1",
                    new BigDecimal("5.00"), BY_THE_OPERATOR, HolderKind.MERCHANT).orElseThrow();

            assertThat(paid.amount()).isEqualByComparingTo("5.00");
            assertThat(paid.retained()).isEqualByComparingTo("35.00");
            assertThat(paid.collections()).isEqualTo(1);
            assertThat(till).allSatisfy(row -> assertThat(row.getClearedBy()).isEqualTo(paid.id()));

            List<CashFloatEntry> rows = written();
            assertThat(rows).hasSize(2);
            CashFloatEntry payment = only(rows, CashFloatEntry.Kind.REMITTED);
            assertThat(payment.getId()).isEqualTo(paid.id());
            assertThat(payment.getAmount()).isEqualByComparingTo("5.00");
            assertThat(payment.getHolderKind()).isEqualTo(HolderKind.MERCHANT);
            assertThat(payment.getHolderRef()).isEqualTo(SHOP);
            assertThat(payment.getRecordedBy()).isEqualTo("op-1");
            assertThat(payment.getMethod()).isEqualTo(CashFloatEntry.Method.CASH);
            assertThat(payment.getRequestKey()).isEqualTo("till-key-0001");
            CashFloatEntry share = only(rows, CashFloatEntry.Kind.RETAINED);
            assertThat(share.getAmount()).isEqualByComparingTo("35.00");
            assertThat(share.getHolderRef()).isEqualTo(SHOP);
            assertThat(share.getRecordedBy()).isEqualTo("op-1");
            // Nothing was handed over, and the payment already carries the key.
            assertThat(share.getMethod()).isNull();
            assertThat(share.getRequestKey()).isNull();
            // The float balances: every note the till held is paid or kept, and none twice.
            assertThat(payment.getAmount().add(share.getAmount())).isEqualByComparingTo("40.00");

            // Only what reached the platform is recorded on the ledger, and with no bank deployed
            // it is settled as it is written rather than left waiting for one (RECON-06).
            ArgumentCaptor<AccountingTransaction> posting =
                    ArgumentCaptor.forClass(AccountingTransaction.class);
            verify(transactions).save(posting.capture());
            assertThat(posting.getValue().getLeg())
                    .isEqualTo(AccountingTransaction.Leg.CASH_REMITTANCE);
            assertThat(posting.getValue().getAmount()).isEqualByComparingTo("5.00");
            assertThat(posting.getValue().getStatus())
                    .isEqualTo(AccountingTransaction.Status.SETTLED_IN_CASH);
            verifyNoInteractions(postings);
        }

        @Test
        @DisplayName("with a bank configured, the commission the shop paid is asked of it")
        void withABankThePaymentIsPosted() {
            List<CashFloatEntry> till = tillHolds(pickup("40.00", "35.00", "5.00"));
            assertThat(till).isNotEmpty();

            cashFloat(SettlementService.SettlementMode.BANK).remit(SHOP, "corr-1",
                    new BigDecimal("5.00"), BY_THE_OPERATOR, HolderKind.MERCHANT).orElseThrow();

            ArgumentCaptor<AccountingTransaction> posting =
                    ArgumentCaptor.forClass(AccountingTransaction.class);
            verify(transactions).save(posting.capture());
            assertThat(posting.getValue().getStatus())
                    .isEqualTo(AccountingTransaction.Status.PENDING);
            verify(postings).request(posting.getValue());
        }

        @Test
        @DisplayName("on a till of several pickups, takes the commission on each and keeps each share")
        void severalPickups() {
            // 40.00 of printing (35.00 the shop's) and 12.50 of copies (10.94 the shop's, 1.56
            // commission): 6.56 to pay, 45.94 kept.
            List<CashFloatEntry> till = tillHolds(pickup("40.00", "35.00", "5.00"),
                    pickup("12.50", "10.94", "1.56"));

            CashFloatService.Remittance paid = cashFloat.remit(SHOP, "corr-1",
                    new BigDecimal("6.56"), BY_THE_OPERATOR, HolderKind.MERCHANT).orElseThrow();

            assertThat(paid.amount()).isEqualByComparingTo("6.56");
            assertThat(paid.retained()).isEqualByComparingTo("45.94");
            assertThat(paid.collections()).isEqualTo(2);
            assertThat(till).allSatisfy(row -> assertThat(row.getClearedBy()).isEqualTo(paid.id()));
            assertThat(only(written(), CashFloatEntry.Kind.RETAINED).getAmount())
                    .isEqualByComparingTo("45.94");
        }

        @Test
        @DisplayName("refuses the whole till as the payment: most of it is the shop's own share")
        void refusesTheWholeTill() {
            List<CashFloatEntry> till = tillHolds(pickup("40.00", "35.00", "5.00"));

            assertThatThrownBy(() -> cashFloat.remit(SHOP, "corr-1", new BigDecimal("40.00"),
                    BY_THE_OPERATOR, HolderKind.MERCHANT))
                    .isInstanceOfSatisfying(CashFloatService.AmountChangedException.class,
                            e -> assertThat(e.current()).isEqualByComparingTo("5.00"));
            nothingRecorded(till);
        }

        @Test
        @DisplayName("records nothing when another pickup was paid at the counter after the page "
                + "loaded")
        void refusesATillThatMoved() {
            List<CashFloatEntry> till = tillHolds(pickup("40.00", "35.00", "5.00"),
                    pickup("12.50", "10.94", "1.56"));

            assertThatThrownBy(() -> cashFloat.remit(SHOP, "corr-1", new BigDecimal("5.00"),
                    BY_THE_OPERATOR, HolderKind.MERCHANT))
                    .isInstanceOfSatisfying(CashFloatService.AmountChangedException.class,
                            e -> assertThat(e.current()).isEqualByComparingTo("6.56"));
            nothingRecorded(till);
        }

        @Test
        @DisplayName("records nothing when no amount was confirmed, as a page from before V52 sends")
        void aShopsPaymentNamesItsFigure() {
            // No body at all: no kind and no amount, the till is all the account holds.
            List<CashFloatEntry> till = List.of(pickup("40.00", "35.00", "5.00"));
            when(floats.outstandingFor(SHOP)).thenReturn(till);

            assertThatThrownBy(() -> cashFloat.remit(SHOP, "corr-1", null,
                    CashFloatEntry.Recorded.nobody()))
                    .isInstanceOf(CashFloatService.AmountRequiredException.class);
            nothingRecorded(till);
        }

        @Test
        @DisplayName("keeps all of a pickup a promotion paid for, posting nothing because nothing "
                + "is owed")
        void aSubsidisedPickupOwesNothing() {
            // 40.00 of goods with a 10.00 code: the customer paid 30.00, the shop's share is 35.00
            // and the platform paid 5.00 in. All 30.00 is the shop's to keep; the other 5.00 is the
            // platform's debt, on the shop's statement.
            UUID order = UUID.randomUUID();
            legs.add(Legs.cashHeldByShop(order, "30.00", SHOP));
            legs.add(Legs.merchantCredit(order, "35.00", SHOP));
            legs.add(Legs.subsidy(order, "5.00"));
            List<CashFloatEntry> till = tillHolds(CashFloatEntry.collected(SHOP,
                    HolderKind.MERCHANT, order, new BigDecimal("30.00"), "USD"));

            CashFloatService.Remittance paid = cashFloat.remit(SHOP, "corr-1",
                    new BigDecimal("0.00"), BY_THE_OPERATOR, HolderKind.MERCHANT).orElseThrow();

            assertThat(paid.amount()).isEqualByComparingTo("0.00");
            assertThat(paid.retained()).isEqualByComparingTo("30.00");
            CashFloatEntry share = only(written(), CashFloatEntry.Kind.RETAINED);
            verify(floats).save(any());
            assertThat(share.getId()).isEqualTo(paid.id());
            // The one row this payment wrote, so it carries the key a second press is answered by.
            assertThat(share.getRequestKey()).isEqualTo("till-key-0001");
            assertThat(till).allSatisfy(row -> assertThat(row.getClearedBy()).isEqualTo(paid.id()));
            verify(transactions, never()).save(any());
            verifyNoInteractions(postings);
        }

        @Test
        @DisplayName("answers a repeated press with the first payment and the share it kept")
        void aRepeatedPressReplays() {
            CashFloatEntry first = CashFloatEntry.remitted(SHOP, HolderKind.MERCHANT,
                    new BigDecimal("6.56"), "USD", BY_THE_OPERATOR);
            when(floats.findByRequestKey("till-key-0001")).thenReturn(Optional.of(first));
            when(floats.countClearedBy(List.of(first.getId())))
                    .thenReturn(List.<Object[]>of(new Object[] {first.getId(), 2L}));
            when(floats.clearedTotal(first.getId())).thenReturn(new BigDecimal("52.50"));

            CashFloatService.Remittance again = cashFloat.remit(SHOP, "corr-2",
                    new BigDecimal("6.56"), BY_THE_OPERATOR, HolderKind.MERCHANT).orElseThrow();

            assertThat(again.replayed()).isTrue();
            assertThat(again.id()).isEqualTo(first.getId());
            assertThat(again.amount()).isEqualByComparingTo("6.56");
            assertThat(again.retained()).isEqualByComparingTo("45.94");
            assertThat(again.collections()).isEqualTo(2);
            verify(floats, never()).outstandingFor(any(), any());
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

            assertThatThrownBy(() -> cashFloat.remit(SHOP, "corr-1", new BigDecimal("5.00"),
                    BY_THE_OPERATOR, HolderKind.MERCHANT))
                    .isInstanceOf(CashFloatService.RequestKeyReusedException.class);
            verify(floats, never()).save(any());
            verifyNoInteractions(postings);
        }
    }

    /**
     * One account that is a shop and a rider at once: a shop that also delivers, which the points
     * ledger already knows as a MERCHANT token carrying DELIVERY too. Its till and its bag are one
     * Keycloak subject's and are settled on different terms, so they are never paid in as one.
     */
    @Nested
    @DisplayName("of an account that also rides")
    class AlsoARider {

        private final CashFloatEntry bag = CashFloatEntry.collected(SHOP, HolderKind.RIDER,
                UUID.randomUUID(), new BigDecimal("13.25"), "USD");
        private final CashFloatEntry till = CashFloatEntry.collected(SHOP, HolderKind.MERCHANT,
                UUID.randomUUID(), new BigDecimal("40.00"), "USD");

        @Test
        @DisplayName("refuses to pay in the till and the bag as one when not told which is paying")
        void notToldWhich() {
            when(floats.outstandingFor(SHOP)).thenReturn(List.of(bag, till));

            assertThatThrownBy(() -> cashFloat().remit(SHOP, "corr-1", new BigDecimal("53.25"),
                    CashFloatEntry.Recorded.nobody()))
                    .isInstanceOf(CashFloatService.HolderKindRequiredException.class);
            assertThat(List.of(bag, till)).allMatch(CashFloatEntry::isOutstanding);
            verify(floats, never()).save(any());
            verify(transactions, never()).save(any());
            verifyNoInteractions(postings);
        }

        @Test
        @DisplayName("told the rider is paying, banks the bag whole, as a rider always did, and "
                + "leaves the till")
        void theRiderPays() {
            when(floats.outstandingFor(SHOP, HolderKind.RIDER)).thenReturn(List.of(bag));

            CashFloatService.Remittance paid = cashFloat().remit(SHOP, "corr-1",
                    new BigDecimal("13.25"), CashFloatEntry.Recorded.nobody(), HolderKind.RIDER)
                    .orElseThrow();

            assertThat(paid.amount()).isEqualByComparingTo("13.25");
            assertThat(paid.retained()).isEqualByComparingTo("0");
            assertThat(bag.getClearedBy()).isEqualTo(paid.id());
            assertThat(till.isOutstanding()).isTrue();
            CashFloatEntry row = only(written(), CashFloatEntry.Kind.REMITTED);
            assertThat(row.getHolderKind()).isEqualTo(HolderKind.RIDER);
            ArgumentCaptor<AccountingTransaction> posting =
                    ArgumentCaptor.forClass(AccountingTransaction.class);
            verify(transactions).save(posting.capture());
            assertThat(posting.getValue().getAmount()).isEqualByComparingTo("13.25");
            verify(floats, never()).outstandingFor(SHOP);
            verify(transactions, never()).findByOrderIdIn(any());
        }

        @Test
        @DisplayName("cashes out as a rider net of the bag alone, never of the shop's till")
        void cashOutNetsTheBagAlone() {
            RiderEarningsService earnings = new RiderEarningsService(riderLedger,
                    org.mockito.Mockito.mock(
                            com.delivery.accounting.domain.RiderCashOutRepository.class),
                    floats, transactions,
                    new com.delivery.accounting.payout.RiderPayoutProviders(List.of(
                            new com.delivery.accounting.payout.ManualPayoutProvider()), "MANUAL"),
                    "ACC-PLATFORM", new BigDecimal("5.00"), new BigDecimal("100.00"), true, "UTC",
                    "USD");
            when(riderLedger.balanceOf(SHOP)).thenReturn(new BigDecimal("20.00"));
            // What the account owes the platform as a rider: its bag. The query reads RIDER rows
            // only, and MerchantCashConstraintTest proves against Postgres that the till is not in it.
            when(floats.riderOwesPlatform(SHOP)).thenReturn(new BigDecimal("13.25"));
            lenient().when(floats.outstandingTotalFor(SHOP, HolderKind.MERCHANT))
                    .thenReturn(new BigDecimal("40.00"));

            // 20.00 earned less the 13.25 bag; the till's 40.00 is the shop's to settle.
            assertThat(earnings.availableFor(SHOP)).isEqualByComparingTo("6.75");
        }
    }
}
