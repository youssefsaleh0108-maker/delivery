package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.CounterpartyKind;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.domain.StatementDispatchRepository;

/**
 * What the platform owes a shop, and how it says so.
 *
 * <p>The property that matters more than any single figure: <strong>the lines sum to the net</strong>.
 * The net is the merchant credits, read straight off the legs and exact; "goods sold" is derived by
 * adding the commission back to it, never computed independently. Compute both from the same source
 * and a rounding remainder eventually leaves a statement whose column does not add up, which is the
 * one defect a merchant will absolutely find.
 *
 * <p>The second property is honesty about what the ledger cannot prove. The platform's leg on an
 * order is a RESIDUE — everything nobody else received — so on an order with a shop AND a delivery
 * company there is nothing that says how much of it is goods commission. The statement does not
 * guess; it declines the split and says so.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("a merchant's statement")
class MerchantStatementTest {

    private static final String SHOP = "merchant-sub-1";
    private static final String CARRIER = "provider-1";

    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private CashFloatRepository floatEntries;
    @Mock
    private RiderLedgerRepository riderLedger;
    @Mock
    private StatementDispatchRepository dispatches;
    @Mock
    private CounterpartyDirectory directory;

    private StatementService service;
    private StatementRange august;

    @BeforeEach
    void setUp() {
        service = new StatementService(transactions, floatEntries, riderLedger, dispatches,
                directory, new BigDecimal("12.5"), "USD", "UTC");
        august = StatementRange.of(LocalDate.parse("2026-08-01"), LocalDate.parse("2026-08-29"),
                ZoneId.of("UTC"));
    }

    private void ledgerHolds(List<AccountingTransaction> own, List<AccountingTransaction> all) {
        when(transactions.legsForCounterparty(eq(CounterpartyKind.MERCHANT), eq(SHOP), any(), any()))
                .thenReturn(own);
        // Lenient: a range with no orders never asks this, which is the engine skipping a query it
        // does not need rather than a stub nobody meant to write.
        lenient().when(transactions.findByOrderIdIn(anyCollection())).thenReturn(all);
        when(directory.nameOf(CounterpartyKind.MERCHANT, SHOP)).thenReturn("Rose & Crust Pizzeria");
    }

    private static BigDecimal summed(Statement statement) {
        return statement.lines().stream()
                .map(line -> line.direction() == Statement.Sign.CREDIT
                        ? line.amount() : line.amount().negate())
                .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    @Nested
    @DisplayName("on ordinary catalog orders")
    class Ordinary {

        private final UUID big = UUID.randomUUID();
        private final UUID small = UUID.randomUUID();

        @BeforeEach
        void twoOrders() {
            // 100.00 of goods at 12.5%: 12.50 commission, 87.50 to the shop.
            // 19.50 of goods at 12.5%: 2.4375, rounded HALF_UP to 2.44, 17.06 to the shop.
            List<AccountingTransaction> own = List.of(
                    Legs.merchantCredit(big, "87.50", SHOP),
                    Legs.merchantCredit(small, "17.06", SHOP));
            List<AccountingTransaction> all = List.of(
                    Legs.cashCollected(big, "100.00", "rider-1"),
                    Legs.merchantCredit(big, "87.50", SHOP),
                    Legs.commission(big, "12.50"),
                    Legs.cashCollected(small, "19.50", "rider-1"),
                    Legs.merchantCredit(small, "17.06", SHOP),
                    Legs.commission(small, "2.44"));
            ledgerHolds(own, all);
        }

        @Test
        @DisplayName("owes the shop exactly what the merchant credits say")
        void netIsTheMerchantCredits() {
            Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

            assertThat(statement.net().amount()).isEqualByComparingTo("104.56");
            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.WE_OWE);
        }

        @Test
        @DisplayName("shows goods sold and commission, and they add up to the net")
        void linesSumToTheNet() {
            Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

            // Two lines and no more: riders carried these orders and took their cash, so the shop's
            // counter lines never appear, and a delivery reads exactly as it did before pickups.
            assertThat(statement.lines()).hasSize(2);
            assertThat(statement.lines().get(0).label()).isEqualTo("Goods sold");
            assertThat(statement.lines().get(0).amount()).isEqualByComparingTo("119.50");
            assertThat(statement.lines().get(0).direction()).isEqualTo(Statement.Sign.CREDIT);
            assertThat(statement.lines().get(1).label()).isEqualTo("Platform commission (12.5%)");
            assertThat(statement.lines().get(1).amount()).isEqualByComparingTo("14.94");
            assertThat(statement.lines().get(1).direction()).isEqualTo(Statement.Sign.DEBIT);

            // The balance property, asserted rather than assumed. Statement.of would have thrown,
            // but stating it here is what stops somebody "fixing" that check away.
            assertThat(summed(statement)).isEqualByComparingTo(statement.net().amount());
        }

        @Test
        @DisplayName("itemises each order with its gross, commission and net")
        void entriesBreakDownEachOrder() {
            Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

            Statement.Entry entry = statement.entries().stream()
                    .filter(e -> e.orderId().equals(small))
                    .findFirst().orElseThrow();

            assertThat(entry.gross()).isEqualByComparingTo("19.50");
            assertThat(entry.commission()).isEqualByComparingTo("2.44");
            assertThat(entry.net()).isEqualByComparingTo("17.06");
            // Read off the collection leg rather than stored a third time.
            assertThat(entry.paymentMethod()).isEqualTo("CASH");
        }

        @Test
        @DisplayName("heads the statement with the shop's name, not its account number")
        void carriesTheName() {
            Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

            assertThat(statement.name()).isEqualTo("Rose & Crust Pizzeria");
            assertThat(statement.ref()).isEqualTo(SHOP);
            assertThat(statement.orders()).isEqualTo(2);
        }
    }

    @Nested
    @DisplayName("when the platform's share cannot be split")
    class Unprovable {

        @Test
        @DisplayName("declines the commission line rather than inventing one")
        void refusesToSplitAResidue() {
            UUID order = UUID.randomUUID();
            // A shop AND a delivery company on one order. The platform's leg is the goods commission
            // plus its cut of the delivery fee, added together, and nothing separates them.
            ledgerHolds(
                    List.of(Legs.merchantCredit(order, "35.00", SHOP)),
                    List.of(
                            Legs.cashCollected(order, "42.50", "rider-1"),
                            Legs.merchantCredit(order, "35.00", SHOP),
                            Legs.providerCredit(order, "2.25", CARRIER),
                            Legs.commission(order, "5.25")));

            Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

            assertThat(statement.lines()).hasSize(1);
            assertThat(statement.lines().get(0).label()).isEqualTo("Goods sold");
            assertThat(statement.lines().get(0).amount()).isEqualByComparingTo("35.00");
            // The net is still exact. That is the number the shop is paid.
            assertThat(statement.net().amount()).isEqualByComparingTo("35.00");
            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.WE_OWE);
            assertThat(statement.note()).contains("cannot be split");
        }

        @Test
        @DisplayName("treats an unidentified payee on the order as somebody else")
        void anUnattributedPayeeBlocksTheSplit() {
            UUID order = UUID.randomUUID();
            ledgerHolds(
                    List.of(Legs.merchantCredit(order, "87.50", SHOP)),
                    List.of(
                            Legs.merchantCredit(order, "87.50", SHOP),
                            // Might be this same rider, might not. "Might" is not a basis for
                            // putting a figure on a statement somebody is going to check.
                            Legs.of(order, AccountingTransaction.Leg.RIDER_CREDIT, "2.25",
                                    AccountingTransaction.Direction.CREDIT, null, null),
                            Legs.commission(order, "12.50")));

            Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

            assertThat(statement.lines()).hasSize(1);
            assertThat(statement.net().amount()).isEqualByComparingTo("87.50");
        }
    }

    @Nested
    @DisplayName("when the platform paid into the order")
    class Subsidised {

        @Test
        @DisplayName("shows a contribution rather than a negative commission")
        void subsidyIsItsOwnLine() {
            UUID order = UUID.randomUUID();
            // Merchant fee waived and a promo code: the shop keeps the whole goods amount and the
            // platform is out of pocket.
            ledgerHolds(
                    List.of(Legs.merchantCredit(order, "40.00", SHOP)),
                    List.of(
                            Legs.cashCollected(order, "37.50", "rider-1"),
                            Legs.merchantCredit(order, "40.00", SHOP),
                            Legs.subsidy(order, "2.50")));

            Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

            assertThat(statement.lines()).hasSize(2);
            assertThat(statement.lines().get(0).amount()).isEqualByComparingTo("37.50");
            assertThat(statement.lines().get(1).label()).isEqualTo("Platform contribution");
            assertThat(statement.lines().get(1).amount()).isEqualByComparingTo("2.50");
            assertThat(statement.lines().get(1).direction()).isEqualTo(Statement.Sign.CREDIT);
            // Still exactly what the shop is owed.
            assertThat(statement.net().amount()).isEqualByComparingTo("40.00");
        }
    }

    @Nested
    @DisplayName("on a wrapped gift")
    class WrappedGift {

        private final UUID gift = UUID.randomUUID();

        @BeforeEach
        void aWrappedGift() {
            // 45.00 of goods at 12.5% and 3.00 of wrapping, paid by card: 39.37 for the goods and
            // 3.00 for the wrapping to the shop, 5.63 of commission to the platform.
            List<AccountingTransaction> own = List.of(
                    Legs.merchantCredit(gift, "39.37", SHOP),
                    Legs.giftWrapCredit(gift, "3.00", SHOP));
            List<AccountingTransaction> all = List.of(
                    Legs.of(gift, AccountingTransaction.Leg.CUSTOMER_DEBIT, "48.00",
                            AccountingTransaction.Direction.DEBIT, null, null),
                    Legs.merchantCredit(gift, "39.37", SHOP),
                    Legs.giftWrapCredit(gift, "3.00", SHOP),
                    Legs.commission(gift, "5.63"));
            ledgerHolds(own, all);
        }

        @Test
        @DisplayName("owes the shop its goods and its wrapping")
        void netCountsTheWrapping() {
            Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

            assertThat(statement.net().amount()).isEqualByComparingTo("42.37");
            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.WE_OWE);
        }

        @Test
        @DisplayName("shows the wrapping on a line of its own, never grossed up with the goods")
        void wrappingIsItsOwnLine() {
            Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

            assertThat(statement.lines()).extracting(Statement.Line::label).containsExactly(
                    "Goods sold", "Platform commission (12.5%)", "Gift wrapping");
            // Commission on the 45.00 of goods, and none on the 3.00 of wrapping.
            assertThat(statement.lines().get(0).amount()).isEqualByComparingTo("45.00");
            assertThat(statement.lines().get(1).amount()).isEqualByComparingTo("5.63");
            assertThat(statement.lines().get(2).amount()).isEqualByComparingTo("3.00");
            assertThat(statement.lines().get(2).direction()).isEqualTo(Statement.Sign.CREDIT);
        }

        @Test
        @DisplayName("counts the wrapping in the gift's own row, which stays one row")
        void theRowCountsTheWrapping() {
            Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

            assertThat(statement.entries()).hasSize(1);
            Statement.Entry entry = statement.entries().get(0);
            assertThat(entry.orderId()).isEqualTo(gift);
            assertThat(entry.gross()).isEqualByComparingTo("48.00");
            assertThat(entry.commission()).isEqualByComparingTo("5.63");
            assertThat(entry.net()).isEqualByComparingTo("42.37");
        }
    }

    /**
     * A shop paid at its own counter for pickups (V52). It keeps its share of that cash and pays the
     * platform its commission, so the statement shows the share as paid to it in cash and asks for
     * the commission on everything still in the till, whenever it was taken — and once that is paid,
     * the shop is square: no statement says the platform owes it the share it kept.
     */
    @Nested
    @DisplayName("paid at its counter for pickups")
    class PickupCash {

        private final UUID pickup = UUID.randomUUID();

        /** 40.00 of printing at 12.5%: 35.00 the shop's, 5.00 commission, all 40.00 in its till. */
        private final List<AccountingTransaction> pickupLegs = List.of(
                Legs.cashHeldByShop(pickup, "40.00", SHOP),
                Legs.merchantCredit(pickup, "35.00", SHOP),
                Legs.commission(pickup, "5.00"));

        /** The shop's own legs on the pickup, as a statement query returns them. */
        private List<AccountingTransaction> shopsOwn() {
            return List.of(pickupLegs.get(0), pickupLegs.get(1));
        }

        private CashFloatEntry tillRow(UUID order, String cash) {
            return CashFloatEntry.collected(SHOP, CashFloatEntry.HolderKind.MERCHANT, order,
                    new BigDecimal(cash), "USD");
        }

        /** What the till holds now, read as a shop's. */
        private void tillHolds(CashFloatEntry... rows) {
            when(floatEntries.heldBy(SHOP, CashFloatEntry.HolderKind.MERCHANT))
                    .thenReturn(List.of(rows));
        }

        @Test
        @DisplayName("before paying, shows the share it kept and owes the platform the commission")
        void beforePaying() {
            ledgerHolds(shopsOwn(), pickupLegs);
            tillHolds(tillRow(pickup, "40.00"));

            Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

            assertThat(statement.lines()).extracting(Statement.Line::label).containsExactly(
                    "Goods sold", "Platform commission (12.5%)",
                    "Your share, kept at your counter", "Commission to pay from your counter");
            assertThat(statement.lines()).extracting(Statement.Line::amount)
                    .usingElementComparator(BigDecimal::compareTo)
                    .containsExactly(new BigDecimal("40.00"), new BigDecimal("5.00"),
                            new BigDecimal("35.00"), new BigDecimal("5.00"));
            assertThat(statement.lines().get(2).direction()).isEqualTo(Statement.Sign.DEBIT);
            assertThat(statement.lines().get(3).direction()).isEqualTo(Statement.Sign.DEBIT);
            assertThat(statement.net().amount()).isEqualByComparingTo("5.00");
            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.THEY_OWE);
            assertThat(summed(statement)).isEqualByComparingTo("-5.00");
        }

        @Test
        @DisplayName("once it has paid the commission, is square, and is never owed the share it "
                + "kept")
        void afterPaying() {
            ledgerHolds(shopsOwn(), pickupLegs);
            // The payment took the pickup out of the till, in this period.
            when(floatEntries.totalForHolderBetween(eq(SHOP),
                    eq(CashFloatEntry.HolderKind.MERCHANT), eq(CashFloatEntry.Kind.REMITTED),
                    any(), any())).thenReturn(new BigDecimal("5.00"));

            Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.SETTLED);
            assertThat(statement.net().amount()).isEqualByComparingTo("0.00");
            assertThat(statement.lines()).extracting(Statement.Line::label).containsExactly(
                    "Goods sold", "Platform commission (12.5%)", "Your share, kept at your counter");
            assertThat(summed(statement)).isEqualByComparingTo("0.00");
            assertThat(statement.note()).contains("You paid the platform 5.00 USD from your counter");
        }

        @Test
        @DisplayName("on a till of several pickups, asks for exactly what the Back Office records")
        void severalPickups() {
            UUID copies = UUID.randomUUID();
            List<AccountingTransaction> all = new ArrayList<>(pickupLegs);
            all.addAll(List.of(
                    Legs.cashHeldByShop(copies, "12.50", SHOP),
                    Legs.merchantCredit(copies, "10.94", SHOP),
                    Legs.commission(copies, "1.56")));
            ledgerHolds(List.of(all.get(0), all.get(1), all.get(3), all.get(4)), all);
            List<CashFloatEntry> till = List.of(tillRow(pickup, "40.00"), tillRow(copies, "12.50"));
            tillHolds(till.toArray(CashFloatEntry[]::new));

            Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

            assertThat(statement.net().amount()).isEqualByComparingTo("6.56");
            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.THEY_OWE);
            // One rule over the same rows as the remittance the operator records.
            assertThat(statement.net().amount())
                    .isEqualByComparingTo(ShopTill.of(SHOP, till, all).owed());
            assertThat(summed(statement)).isEqualByComparingTo("-6.56");
        }

        @Test
        @DisplayName("asks for the commission still in the till from an earlier period")
        void anEarlierPeriodsTill() {
            // Nothing sold in August; July's pickup is still in the till.
            ledgerHolds(List.of(), pickupLegs);
            tillHolds(tillRow(pickup, "40.00"));

            Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

            assertThat(statement.lines()).singleElement().satisfies(line -> {
                assertThat(line.label()).isEqualTo("Commission to pay from your counter");
                assertThat(line.amount()).isEqualByComparingTo("5.00");
                assertThat(line.direction()).isEqualTo(Statement.Sign.DEBIT);
            });
            assertThat(statement.net().amount()).isEqualByComparingTo("5.00");
            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.THEY_OWE);
        }

        @Test
        @DisplayName("still itemises the order by its goods, paid in cash")
        void theRowIsTheGoods() {
            ledgerHolds(shopsOwn(), pickupLegs);
            tillHolds(tillRow(pickup, "40.00"));

            Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

            assertThat(statement.entries()).singleElement().satisfies(entry -> {
                assertThat(entry.gross()).isEqualByComparingTo("40.00");
                assertThat(entry.commission()).isEqualByComparingTo("5.00");
                assertThat(entry.net()).isEqualByComparingTo("35.00");
                assertThat(entry.paymentMethod()).isEqualTo("CASH");
            });
            assertThat(statement.orders()).isEqualTo(1);
        }

        @Test
        @DisplayName("says the shop keeps its share and pays the commission, in the words it is sent")
        void theRenderedLinesSayWhoseCashItIs() {
            ledgerHolds(shopsOwn(), pickupLegs);
            tillHolds(tillRow(pickup, "40.00"));

            String body = new StatementRenderer()
                    .body(service.build(CounterpartyKind.MERCHANT, SHOP, august));

            assertThat(body)
                    .contains("-35.00  Your share, kept at your counter (paid to you in cash by "
                            + "your customers on pickup orders)")
                    .contains("-5.00  Commission to pay from your counter (cash your customers "
                            + "paid at your counter — you keep your share and pay the platform its "
                            + "commission, including any not yet paid from earlier periods)")
                    .contains("You owe the platform 5.00 USD.")
                    // The whole till was never the platform's money: most of it is the shop's.
                    .doesNotContain("platform's money");
        }
    }

    /**
     * One account that is a shop and a rider at once — a shop that also delivers. Its till and its
     * bag belong to one Keycloak subject, and each statement counts only its own.
     */
    @Nested
    @DisplayName("of an account that also rides")
    class AlsoARider {

        private final UUID pickup = UUID.randomUUID();
        private final UUID delivery = UUID.randomUUID();

        @BeforeEach
        void bothKindsOfCash() {
            // 40.00 of a pickup in the shop's till, and 13.25 the same account took at a door.
            CashFloatEntry till = CashFloatEntry.collected(SHOP, CashFloatEntry.HolderKind.MERCHANT,
                    pickup, new BigDecimal("40.00"), "USD");
            CashFloatEntry bag = CashFloatEntry.collected(SHOP, CashFloatEntry.HolderKind.RIDER,
                    delivery, new BigDecimal("13.25"), "USD");
            lenient().when(floatEntries.heldBy(SHOP, CashFloatEntry.HolderKind.MERCHANT))
                    .thenReturn(List.of(till));
            lenient().when(floatEntries.heldBy(SHOP, CashFloatEntry.HolderKind.RIDER))
                    .thenReturn(List.of(bag));
            lenient().when(floatEntries.forHolderBetween(eq(SHOP),
                    eq(CashFloatEntry.HolderKind.MERCHANT), eq(CashFloatEntry.Kind.COLLECTED),
                    any(), any())).thenReturn(List.of(till));
            lenient().when(floatEntries.forHolderBetween(eq(SHOP),
                    eq(CashFloatEntry.HolderKind.RIDER), eq(CashFloatEntry.Kind.COLLECTED),
                    any(), any())).thenReturn(List.of(bag));
            lenient().when(floatEntries.outstandingTotalFor(SHOP, CashFloatEntry.HolderKind.MERCHANT))
                    .thenReturn(new BigDecimal("40.00"));
            lenient().when(floatEntries.outstandingTotalFor(SHOP, CashFloatEntry.HolderKind.RIDER))
                    .thenReturn(new BigDecimal("13.25"));
        }

        @Test
        @DisplayName("the shop's statement counts its till and never the bag")
        void theShopCountsItsTill() {
            List<AccountingTransaction> legs = List.of(
                    Legs.cashHeldByShop(pickup, "40.00", SHOP),
                    Legs.merchantCredit(pickup, "35.00", SHOP),
                    Legs.commission(pickup, "5.00"));
            ledgerHolds(List.of(legs.get(0), legs.get(1)), legs);

            Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

            // The commission on the till alone; the bag is not the shop's to pay in.
            assertThat(statement.net().amount()).isEqualByComparingTo("5.00");
            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.THEY_OWE);
            verify(floatEntries, never()).heldBy(eq(SHOP), eq(CashFloatEntry.HolderKind.RIDER));
        }

        @Test
        @DisplayName("the rider's statement counts the bag and never the till")
        void theRiderCountsTheBag() {
            when(transactions.legsForCounterparty(eq(CounterpartyKind.RIDER), eq(SHOP), any(),
                    any())).thenReturn(List.of());
            when(riderLedger.between(eq(SHOP), any(), any())).thenReturn(List.of());
            when(floatEntries.totalForHolderBetween(eq(SHOP), eq(CashFloatEntry.HolderKind.RIDER),
                    eq(CashFloatEntry.Kind.REMITTED), any(), any())).thenReturn(BigDecimal.ZERO);
            when(directory.nameOf(CounterpartyKind.RIDER, SHOP)).thenReturn("Rose & Crust Pizzeria");

            Statement statement = service.build(CounterpartyKind.RIDER, SHOP, august);

            // The 13.25 taken at a door; the till's 40.00 is the shop's business.
            assertThat(statement.net().amount()).isEqualByComparingTo("13.25");
            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.THEY_OWE);
            // Nor does the till creep into the "currently holding" note.
            assertThat(statement.note()).isNull();
        }
    }

    @Test
    @DisplayName("a shop with no orders in the range is settled, not broken")
    void emptyRangeIsSettled() {
        ledgerHolds(List.of(), List.of());

        Statement statement = service.build(CounterpartyKind.MERCHANT, SHOP, august);

        assertThat(statement.lines()).isEmpty();
        assertThat(statement.net().amount()).isEqualByComparingTo("0.00");
        assertThat(statement.net().direction()).isEqualTo(Statement.Direction.SETTLED);
        assertThat(statement.entries()).isEmpty();
    }
}
