package com.delivery.accounting.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Bean;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.PointsEntry;
import com.delivery.accounting.domain.PointsEntry.OwnerKind;
import com.delivery.accounting.domain.PointsEntryRepository;
import com.delivery.accounting.event.OrderEventListener;
import com.delivery.accounting.payout.ManualPayoutProvider;
import com.delivery.accounting.payout.RiderPayoutProviders;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * RECON-04: re-driving a settlement that failed part-way, against a real Postgres.
 *
 * <p>The two orders stuck on dev since 2026-09-08 are not untouched. Their loyalty points were
 * awarded by the run that failed; only the ledger rows are missing. The first attempt at recovery
 * ran the whole re-drive in one transaction, so the duplicate those points caused — tolerated
 * everywhere else — aborted it: Postgres refuses every further statement on a transaction one has
 * failed in, and the order stayed unsettled with a 500 for an answer.
 *
 * <p>So the constraint IS the test, and it needs a real database:
 *
 * <pre>
 * docker run --rm -d --name acct-pg -p 55533:5432 -e POSTGRES_PASSWORD=test -e POSTGRES_DB=accounting postgis/postgis:17-3.5
 * docker exec acct-pg psql -U postgres -d accounting -c "create schema accounting"
 * mvn -o -pl services/accounting-service -am test -Dtest=SettlementRedrivePostgresTest \
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
@Import({SettlementRecovery.class, SettlementFailures.class, SettlementService.class,
        CashFloatService.class, PointsService.class, RiderEarningsService.class,
        RiderPayoutProviders.class, ManualPayoutProvider.class, OrderEventListener.class,
        SettlementRedrivePostgresTest.Json.class})
@EnabledIfSystemProperty(named = "delivery.test.postgres", matches = "true")
// Real commits: what is being proved is that one statement failing does not take the rest with it.
@Transactional(propagation = Propagation.NOT_SUPPORTED)
@DisplayName("RECON-04: re-driving a part-settled order, against Postgres")
class SettlementRedrivePostgresTest {

    /** The listener and the recovery both read events with one. */
    @TestConfiguration
    static class Json {
        @Bean
        ObjectMapper objectMapper() {
            return new ObjectMapper();
        }
    }

    private static final String TOKEN = "operator-token";

    /** Where the carrier company is paid, as Order Manager tells the back office. */
    private static final String COMPANY_ACCOUNT = "ACC-FLEET-7";

    @MockitoBean
    private OrderManagerOrdersClient orderManager;
    @MockitoBean
    private AccountDirectory accounts;
    @MockitoBean
    private BankPostingPublisher postings;

    @Autowired
    private SettlementRecovery recovery;
    @Autowired
    private AccountingTransactionRepository transactions;
    @Autowired
    private PointsEntryRepository points;
    @Autowired
    private ObjectMapper objectMapper;

    private UUID order;
    private String shop;
    private String company;
    private String rider;

    @BeforeEach
    void setUp() {
        order = UUID.randomUUID();
        shop = "merchant-" + UUID.randomUUID();
        company = "provider-" + UUID.randomUUID();
        rider = "rider-" + UUID.randomUUID();
        when(accounts.forUser(any())).thenReturn("ACC-UNMAPPED");
    }

    /**
     * Dev's stuck order, as Order Manager still has it: 13.11 of goods and a 4.72 delivery,
     * discounted to nothing by a code, paid in cash at the door, delivered on 8 September.
     */
    private JsonNode asOrderManagerHasIt() throws Exception {
        return objectMapper.readTree("""
                {"id":"%s","kind":"CATALOG","customerId":"customer-1","merchantId":"%s",
                 "riderId":"%s","deliveryProviderId":"%s","deliveryProviderAccount":"%s",
                 "status":"DELIVERED",
                 "totalAmount":0.00,"subtotal":13.11,"deliveryFee":4.72,"expressSurcharge":0.00,
                 "deliveryFeeWaived":false,"merchantFeeWaived":false,"carrierFeeWaived":false,
                 "discountAmount":17.83,"paymentMethod":"CASH","paymentStatus":"COLLECTED",
                 "fulfilment":"DELIVERY","deliveredAt":"2026-09-08T21:16:14Z"}
                """.formatted(order, shop, rider, company, COMPANY_ACCOUNT));
    }

    /** What the failed run of 09-08 left behind: the points, and nothing else. */
    private void pointsAlreadyAwarded() {
        points.saveAndFlush(PointsEntry.earned(OwnerKind.MERCHANT, shop, order, 65, null));
        points.saveAndFlush(PointsEntry.earned(OwnerKind.CARRIER, company, order, 47, rider));
    }

    private long earnedRowsFor(OwnerKind kind, String ref) {
        return points.findByOwnerKindAndOwnerRefOrderByCreatedAtDesc(kind, ref,
                        org.springframework.data.domain.PageRequest.of(0, 50)).stream()
                .filter(row -> order.equals(row.getOrderId()))
                .filter(row -> row.getReason() == PointsEntry.Reason.ORDER_EARNED)
                .count();
    }

    @Test
    @DisplayName("completes the ledger although the points were already awarded, and twice is a no-op")
    void completesWhatIsMissingAndLeavesWhatIsThere() throws Exception {
        pointsAlreadyAwarded();
        when(orderManager.order(eq(TOKEN), eq(order))).thenReturn(asOrderManagerHasIt());
        assertThat(transactions.existsByOrderId(order)).isFalse();

        SettlementRecovery.Settled settled = recovery.settle(TOKEN, order, "op-1");

        assertThat(settled.settled()).isTrue();
        List<AccountingTransaction> legs = transactions.findByOrderIdOrderByCreatedAt(order);
        // The shop is owed its goods less commission and the company its fee less the cut; the
        // platform funded the code that took the bill to nothing.
        assertThat(legs).extracting(AccountingTransaction::getLeg)
                .containsExactlyInAnyOrder(AccountingTransaction.Leg.MERCHANT_CREDIT,
                        AccountingTransaction.Leg.PROVIDER_CREDIT,
                        AccountingTransaction.Leg.PLATFORM_SUBSIDY);
        assertThat(legs).filteredOn(leg -> leg.getLeg() == AccountingTransaction.Leg.MERCHANT_CREDIT)
                .singleElement()
                .satisfies(leg -> assertThat(leg.getAmount()).isEqualByComparingTo("11.47"));
        assertThat(legs).filteredOn(leg -> leg.getLeg() == AccountingTransaction.Leg.PROVIDER_CREDIT)
                .singleElement()
                .satisfies(leg -> {
                    assertThat(leg.getAmount()).isEqualByComparingTo("4.25");
                    // And in the company's own account, not the placeholder: Order Manager tells
                    // the back office where the company is paid, and this read is the back
                    // office's. A re-drive lands where the first settlement would have.
                    assertThat(leg.getAccountRef()).isEqualTo(COMPANY_ACCOUNT);
                });
        // Nobody earned their points a second time.
        assertThat(earnedRowsFor(OwnerKind.MERCHANT, shop)).isEqualTo(1);
        assertThat(earnedRowsFor(OwnerKind.CARRIER, company)).isEqualTo(1);

        SettlementRecovery.Settled again = recovery.settle(TOKEN, order, "op-1");

        assertThat(again.settled()).isFalse();
        assertThat(again.reason()).contains("already in the ledger");
        assertThat(transactions.findByOrderIdOrderByCreatedAt(order)).hasSameSizeAs(legs);
        assertThat(earnedRowsFor(OwnerKind.MERCHANT, shop)).isEqualTo(1);
    }

    @Test
    @DisplayName("the check finds it: delivered in Order Manager, no ledger rows")
    void theCheckFindsIt() throws Exception {
        pointsAlreadyAwarded();
        when(orderManager.delivered(eq(TOKEN), anyInt())).thenReturn(
                new OrderManagerOrdersClient.Delivered(List.of(asOrderManagerHasIt()), true));

        SettlementRecovery.Check before = recovery.unsettledDeliveries(TOKEN, 1000);

        // Points are not evidence of a settlement; only legs are.
        assertThat(before.missing()).extracting(SettlementRecovery.Missing::orderId)
                .contains(order);
        assertThat(before.complete()).isTrue();
        assertThat(before.scanned()).isEqualTo(1);

        when(orderManager.order(eq(TOKEN), eq(order))).thenReturn(asOrderManagerHasIt());
        recovery.settle(TOKEN, order, "op-1");

        SettlementRecovery.Check after = recovery.unsettledDeliveries(TOKEN, 1000);

        assertThat(after.missing()).extracting(SettlementRecovery.Missing::orderId)
                .doesNotContain(order);
    }
}
