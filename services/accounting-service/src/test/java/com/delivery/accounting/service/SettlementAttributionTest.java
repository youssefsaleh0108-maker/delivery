package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.CounterpartyKind;
import com.delivery.accounting.domain.RiderLedgerRepository;

/**
 * Who each leg is for, which the ledger could not say until now.
 *
 * <p>The problem this fixes is not hypothetical: every merchant credit written so far points at one
 * omnibus {@code ACC-MERCHANT}, because {@code account_ref} is resolved from a Keycloak attribute
 * nobody has set. The account is not wrong — it is what a bank posting would use — it simply is not
 * an identity. So the tests here are all the same shape: the identity lands on the leg, and
 * {@code account_ref} is untouched beside it.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("attributing a settlement's legs to the parties it is about")
class SettlementAttributionTest {

    private static final String CUSTOMER_ACCOUNT = "ACC-CUSTOMER";
    private static final String MERCHANT_ACCOUNT = "ACC-MERCHANT";
    private static final String CARRIER_ACCOUNT = "ACC-CARRIER";
    private static final String PLATFORM_ACCOUNT = "ACC-PLATFORM";

    private static final String MERCHANT_ID = "merchant-sub-1";
    private static final String RIDER_ID = "rider-sub-1";
    private static final String CARRIER_ID = "provider-uuid-1";

    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private CashFloatRepository floatEntries;
    @Mock
    private RiderLedgerRepository riderLedger;
    @Mock
    private BankPostingPublisher postings;

    private SettlementService service;
    private UUID orderId;

    @BeforeEach
    void setUp() {
        orderId = UUID.randomUUID();
        service = new SettlementService(transactions, floatEntries, riderLedger, postings,
                new BigDecimal("12.5"), new BigDecimal("10"), "",
                PLATFORM_ACCOUNT, "USD", SettlementService.SettlementMode.LEDGER_ONLY);
    }

    /**
     * The legs as they were written.
     *
     * <p>{@code atLeastOnce}, because LEDGER_ONLY saves twice: once with the legs as built, and
     * again once they have been marked discharged outside any bank. The first capture is the one
     * that proves what settlement decided.
     */
    private List<AccountingTransaction> saved() {
        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<AccountingTransaction>> captor = ArgumentCaptor.forClass(List.class);
        verify(transactions, org.mockito.Mockito.atLeastOnce()).saveAll(captor.capture());
        return captor.getAllValues().get(0);
    }

    private static AccountingTransaction leg(List<AccountingTransaction> legs, Leg which) {
        return legs.stream().filter(t -> t.getLeg() == which).findFirst().orElseThrow();
    }

    @Nested
    @DisplayName("a catalog order")
    class CatalogOrder {

        @Test
        @DisplayName("names the shop on the merchant leg without touching its account")
        void merchantLegCarriesTheShop() {
            service.settle(orderId, new BigDecimal("100.00"), new BigDecimal("100.00"),
                    CUSTOMER_ACCOUNT, MERCHANT_ACCOUNT, null, null, "corr",
                    SettlementService.Waivers.none(), null, null,
                    new SettlementService.Parties(MERCHANT_ID, null));

            AccountingTransaction merchant = leg(saved(), Leg.MERCHANT_CREDIT);
            assertThat(merchant.getCounterpartyKind()).isEqualTo(CounterpartyKind.MERCHANT);
            assertThat(merchant.getCounterpartyRef()).isEqualTo(MERCHANT_ID);
            // The whole point of a second pair of columns: the posting account is unchanged, and it
            // is still the omnibus bucket it always was.
            assertThat(merchant.getAccountRef()).isEqualTo(MERCHANT_ACCOUNT);
        }

        @Test
        @DisplayName("puts the platform's own legs under one constant, not an account number")
        void platformLegCarriesTheConstant() {
            service.settle(orderId, new BigDecimal("100.00"), new BigDecimal("100.00"),
                    CUSTOMER_ACCOUNT, MERCHANT_ACCOUNT, null, null, "corr",
                    SettlementService.Waivers.none(), null, null,
                    new SettlementService.Parties(MERCHANT_ID, null));

            AccountingTransaction platform = leg(saved(), Leg.PLATFORM_COMMISSION);
            assertThat(platform.getCounterpartyKind()).isEqualTo(CounterpartyKind.PLATFORM);
            assertThat(platform.getCounterpartyRef()).isEqualTo(CounterpartyKind.PLATFORM_REF);
            // Deliberately not the configurable bank account: a statement whose identity changed
            // when somebody edited a property file would split the platform's history in two.
            assertThat(platform.getCounterpartyRef()).isNotEqualTo(PLATFORM_ACCOUNT);
        }

        @Test
        @DisplayName("names the delivery company on the provider leg")
        void providerLegCarriesTheCarrier() {
            service.settle(orderId, new BigDecimal("42.50"), new BigDecimal("40.00"),
                    CUSTOMER_ACCOUNT, MERCHANT_ACCOUNT, CARRIER_ACCOUNT, null, "corr",
                    new SettlementService.Waivers(new BigDecimal("2.50"), false, false, false),
                    null, null, new SettlementService.Parties(MERCHANT_ID, CARRIER_ID));

            AccountingTransaction provider = leg(saved(), Leg.PROVIDER_CREDIT);
            assertThat(provider.getCounterpartyKind()).isEqualTo(CounterpartyKind.CARRIER);
            assertThat(provider.getCounterpartyRef()).isEqualTo(CARRIER_ID);
        }

        @Test
        @DisplayName("names the rider on the cash leg, because they are holding the notes")
        void cashLegCarriesTheHolder() {
            service.settle(orderId, new BigDecimal("100.00"), new BigDecimal("100.00"),
                    CUSTOMER_ACCOUNT, MERCHANT_ACCOUNT, null,
                    new SettlementService.CashHolder(RIDER_ID, CashFloatEntry.HolderKind.RIDER),
                    "corr", SettlementService.Waivers.none(), null, null,
                    new SettlementService.Parties(MERCHANT_ID, null));

            AccountingTransaction cash = leg(saved(), Leg.CASH_COLLECTED);
            assertThat(cash.getCounterpartyKind()).isEqualTo(CounterpartyKind.RIDER);
            assertThat(cash.getCounterpartyRef()).isEqualTo(RIDER_ID);
        }

        @Test
        @DisplayName("leaves a card customer's debit unattributed, because they are not a counterparty")
        void customerDebitIsNotACounterparty() {
            service.settle(orderId, new BigDecimal("100.00"), new BigDecimal("100.00"),
                    CUSTOMER_ACCOUNT, MERCHANT_ACCOUNT, null, null, "corr",
                    SettlementService.Waivers.none(), null, null,
                    new SettlementService.Parties(MERCHANT_ID, null));

            // A customer is the other side of a collection, not somebody the platform settles with.
            // Attributing them would put every order in the counterparties listing and leave the
            // unattributed total permanently above zero.
            assertThat(leg(saved(), Leg.CUSTOMER_DEBIT).isAttributed()).isFalse();
        }

        @Test
        @DisplayName("credits a platform rider under their own subject")
        void riderLegCarriesTheRider() {
            SettlementService.Rider rider = new SettlementService.Rider(
                    RIDER_ID, "ACC-RIDER", null, "customer-1");

            service.settle(orderId, new BigDecimal("42.50"), new BigDecimal("40.00"),
                    CUSTOMER_ACCOUNT, MERCHANT_ACCOUNT, null, null, "corr",
                    new SettlementService.Waivers(new BigDecimal("2.50"), false, false, false),
                    rider, null, new SettlementService.Parties(MERCHANT_ID, null));

            AccountingTransaction credit = leg(saved(), Leg.RIDER_CREDIT);
            assertThat(credit.getCounterpartyKind()).isEqualTo(CounterpartyKind.RIDER);
            assertThat(credit.getCounterpartyRef()).isEqualTo(RIDER_ID);
        }
    }

    @Nested
    @DisplayName("an errand")
    class Errand {

        @Test
        @DisplayName("names the rider who ran it on their credit")
        void riderCreditIsAttributed() {
            SettlementService.Rider rider = new SettlementService.Rider(
                    RIDER_ID, "ACC-RIDER", null, "customer-1");

            service.settleErrand(orderId, new BigDecimal("30.00"), new BigDecimal("20.00"),
                    CUSTOMER_ACCOUNT, "ACC-RIDER", null, "corr", rider, null);

            AccountingTransaction credit = leg(saved(), Leg.RIDER_CREDIT);
            assertThat(credit.getCounterpartyKind()).isEqualTo(CounterpartyKind.RIDER);
            assertThat(credit.getCounterpartyRef()).isEqualTo(RIDER_ID);
        }
    }

    @Nested
    @DisplayName("when the event names nobody")
    class Unnamed {

        @Test
        @DisplayName("leaves the leg honestly unattributed rather than guessing")
        void anUnnamedMerchantStaysNull() {
            // The pre-attribution overload, which is what every existing caller and every event
            // published before this change looks like.
            service.settle(orderId, new BigDecimal("100.00"), new BigDecimal("100.00"),
                    CUSTOMER_ACCOUNT, MERCHANT_ACCOUNT, null, null, "corr");

            AccountingTransaction merchant = leg(saved(), Leg.MERCHANT_CREDIT);
            assertThat(merchant.isAttributed()).isFalse();
            assertThat(merchant.getCounterpartyRef()).isNull();
            // And it still settles: attribution is additional information, never a precondition.
            assertThat(merchant.getAmount()).isEqualByComparingTo("87.50");
        }

        @Test
        @DisplayName("never records half an identity")
        void kindAndRefMoveTogether() {
            service.settle(orderId, new BigDecimal("100.00"), new BigDecimal("100.00"),
                    CUSTOMER_ACCOUNT, MERCHANT_ACCOUNT, null, null, "corr",
                    SettlementService.Waivers.none(), null, null,
                    // A merchant id that never arrived on the event.
                    new SettlementService.Parties(null, null));

            AccountingTransaction merchant = leg(saved(), Leg.MERCHANT_CREDIT);
            // A kind with no ref names a category and not a party. A statement query would skip it
            // and a reconciliation total would count it, which is the worst of both.
            assertThat(merchant.getCounterpartyKind()).isNull();
            assertThat(merchant.getCounterpartyRef()).isNull();
        }
    }

    @Test
    @DisplayName("settles the same amounts it always did")
    void attributionDoesNotChangeTheArithmetic() {
        service.settle(orderId, new BigDecimal("100.00"), new BigDecimal("100.00"),
                CUSTOMER_ACCOUNT, MERCHANT_ACCOUNT, null, null, "corr",
                SettlementService.Waivers.none(), null, null,
                new SettlementService.Parties(MERCHANT_ID, null));

        List<AccountingTransaction> legs = saved();
        assertThat(leg(legs, Leg.MERCHANT_CREDIT).getAmount()).isEqualByComparingTo("87.50");
        assertThat(leg(legs, Leg.PLATFORM_COMMISSION).getAmount()).isEqualByComparingTo("12.50");
        // The money property this codebase is built on: the legs sum to what the customer paid.
        assertThat(leg(legs, Leg.MERCHANT_CREDIT).getAmount()
                .add(leg(legs, Leg.PLATFORM_COMMISSION).getAmount()))
                .isEqualByComparingTo(leg(legs, Leg.CUSTOMER_DEBIT).getAmount());
        verify(postings, org.mockito.Mockito.never()).request(any());
    }
}
