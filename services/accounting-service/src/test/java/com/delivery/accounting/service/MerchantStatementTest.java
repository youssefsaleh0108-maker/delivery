package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.eq;
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
        org.mockito.Mockito.lenient()
                .when(transactions.findByOrderIdIn(anyCollection())).thenReturn(all);
        when(directory.nameOf(CounterpartyKind.MERCHANT, SHOP)).thenReturn("Rose & Crust Pizzeria");
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

            assertThat(statement.lines()).hasSize(2);
            assertThat(statement.lines().get(0).label()).isEqualTo("Goods sold");
            assertThat(statement.lines().get(0).amount()).isEqualByComparingTo("119.50");
            assertThat(statement.lines().get(0).direction()).isEqualTo(Statement.Sign.CREDIT);
            assertThat(statement.lines().get(1).label()).isEqualTo("Platform commission (12.5%)");
            assertThat(statement.lines().get(1).amount()).isEqualByComparingTo("14.94");
            assertThat(statement.lines().get(1).direction()).isEqualTo(Statement.Sign.DEBIT);

            // The balance property, asserted rather than assumed. Statement.of would have thrown,
            // but stating it here is what stops somebody "fixing" that check away.
            BigDecimal summed = statement.lines().stream()
                    .map(line -> line.direction() == Statement.Sign.CREDIT
                            ? line.amount() : line.amount().negate())
                    .reduce(BigDecimal.ZERO, BigDecimal::add);
            assertThat(summed).isEqualByComparingTo(statement.net().amount());
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
