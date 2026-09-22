package com.delivery.accounting.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.PointsEntryRepository;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.event.OrderEventListener;
import com.delivery.accounting.payout.ManualPayoutProvider;
import com.delivery.accounting.payout.RiderPayoutProviders;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * A table order leaves the ledger untouched — counted in a real database, not in mocks.
 *
 * <p>{@link AccountingTableOrderTest} says the same thing against mocked repositories, and says it
 * faster. This one exists because of what the two fail on. A mock test fails when somebody changes
 * <em>this service</em>; it passes happily if the rows arrive by a route nobody mocked — a
 * cascade, a listener added later, a trigger, a second call site. <strong>Rows in tables are the
 * assertion that cannot be argued with</strong>, and "a restaurant was billed commission on meals
 * it served itself" is exactly the kind of bug that is found months later by an accountant rather
 * than by a build.
 *
 * <p>It is written as a comparison rather than as an absolute, because an absolute proves less: an
 * empty ledger is also what you get from a listener that silently did nothing at all. So the same
 * meal is settled twice — once as a service order collected at a shop counter, which writes legs, a
 * float row and points, and once as a table order, which must write none — and the second is
 * measured as a delta against the first. If the gate is removed, the counts move and this fails
 * pointing at the rows a restaurant would have been chased for.
 *
 * <pre>
 * docker run --rm -d --name acct-pg -p 55533:5432 -e POSTGRES_PASSWORD=test -e POSTGRES_DB=accounting postgis/postgis:17-3.5
 * docker exec acct-pg psql -U postgres -d accounting -c "create schema accounting"
 * mvn -o -pl services/accounting-service -am test -Dtest=AccountingTableOrderDatabaseTest \
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
@Import({SettlementService.class, CashFloatService.class, PointsService.class, SettlementFailures.class,
        RiderEarningsService.class, RiderPayoutProviders.class, ManualPayoutProvider.class,
        OrderEventListener.class, AccountingTableOrderDatabaseTest.Json.class})
@EnabledIfSystemProperty(named = "delivery.test.postgres", matches = "true")
// Real commits: what is being counted is what a database actually holds afterwards.
@Transactional(propagation = Propagation.NOT_SUPPORTED)
@DisplayName("a table order books nothing, counted in Postgres")
class AccountingTableOrderDatabaseTest {

    /** The listener reads events with one. */
    @TestConfiguration
    static class Json {
        @Bean
        ObjectMapper objectMapper() {
            return new ObjectMapper();
        }
    }

    @MockitoBean
    private AccountDirectory accounts;
    @MockitoBean
    private BankPostingPublisher postings;

    @Autowired
    private OrderEventListener listener;
    @Autowired
    private AccountingTransactionRepository transactions;
    @Autowired
    private CashFloatRepository floats;
    @Autowired
    private PointsEntryRepository points;
    @Autowired
    private RiderLedgerRepository riderLedger;

    private String merchant;

    @BeforeEach
    void setUp() {
        merchant = "merchant-" + UUID.randomUUID();
        when(accounts.forUser(any())).thenReturn("ACC-UNMAPPED");
    }

    /**
     * Nine dollars and a quarter of mezze, as {@code OrderSnapshot} serialises it.
     *
     * @param kind       {@code TABLE} or, for the comparison, {@code SERVICE}
     * @param fulfilment {@code DINE_IN} or {@code PICKUP}
     */
    private String meal(UUID orderId, String kind, String fulfilment) {
        return """
                {"orderId":"%s","kind":"%s","customerId":"table:%s","merchantId":"%s",
                 "riderId":null,"deliveryProviderId":null,"deliveryProviderAccount":null,
                 "status":"DELIVERED","totalAmount":9.25,"subtotal":9.25,"deliveryFee":0,
                 "expressSurcharge":0,"giftWrapFee":0,"deliveryFeeWaived":false,
                 "merchantFeeWaived":false,"carrierFeeWaived":false,"discountAmount":0,
                 "paymentMethod":"CASH","paymentStatus":"COLLECTED","deliveryAddress":null,
                 "fulfilment":"%s","tableLabel":7,
                 "occurredAt":"2026-09-22T19:40:00Z"}
                """.formatted(orderId, kind, UUID.randomUUID(), merchant, fulfilment);
    }

    private record Counts(long legs, long floats, long points, long riderLedger) {
    }

    private Counts everything() {
        return new Counts(transactions.count(), floats.count(), points.count(),
                riderLedger.count());
    }

    /**
     * The whole of it, in one test, because the two halves only mean something together.
     *
     * <p>First the same meal at a counter, to show the harness settles and the database is being
     * written to at all. Then the table order, measured as a delta: not one row anywhere.
     */
    @Test
    @DisplayName("the counter settles and the table books nothing: no leg, no float, no points")
    void aTableOrderWritesNoRowAnywhere() {
        UUID counter = UUID.randomUUID();
        Counts before = everything();

        listener.onOrderEvent(meal(counter, "SERVICE", "PICKUP"), "order.delivered", null, "c-1");

        Counts afterCounter = everything();
        assertThat(transactions.findByOrderIdOrderByCreatedAt(counter))
                .as("the comparison settles, so an empty ledger below means the gate and not a "
                        + "listener that does nothing")
                .isNotEmpty();
        assertThat(afterCounter.legs()).isGreaterThan(before.legs());
        assertThat(afterCounter.floats()).isGreaterThan(before.floats());

        UUID table = UUID.randomUUID();
        listener.onOrderEvent(meal(table, "TABLE", "DINE_IN"), "order.delivered", null, "c-2");

        assertThat(transactions.findByOrderIdOrderByCreatedAt(table))
                .as("a table order has no leg of any kind")
                .isEmpty();
        assertThat(everything())
                .as("and moved nothing else: no cash float, no points, no rider ledger")
                .isEqualTo(afterCounter);
    }

    /**
     * And again for a cancellation, which is the other door into this service.
     *
     * <p>Unreachable today — a table order is never picked up — so this is the test that notices
     * the day it becomes reachable, rather than the accountant.
     */
    @Test
    @DisplayName("a cancelled table order compensates nobody")
    void aCancelledTableOrderWritesNoRowEither() {
        Counts before = everything();
        String cancelled = meal(UUID.randomUUID(), "TABLE", "DINE_IN")
                .replace("\"status\":\"DELIVERED\"",
                        "\"status\":\"CANCELLED\",\"stage\":\"AFTER_PICKUP\","
                                + "\"compensateMerchant\":true,\"compensateCarrier\":true");

        listener.onOrderEvent(cancelled, "order.cancelled", null, "c-3");

        assertThat(everything()).isEqualTo(before);
    }
}
