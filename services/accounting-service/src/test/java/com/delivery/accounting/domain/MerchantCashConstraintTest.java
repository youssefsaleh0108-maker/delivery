package com.delivery.accounting.domain;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.TestPropertySource;

/**
 * A shop holding pickup cash (V52), against a real Postgres.
 *
 * <p>The mocked tests prove settlement names the shop as the holder; none can prove the database
 * takes the row, reads its kind back through the queries the Back Office and the statements use,
 * refuses a shop's row that names a delivery company, and still holds every value the checks V52
 * does not touch were last given. These do.
 *
 * <p><strong>Skipped unless a database is there</strong>, like {@link CarrierPayrollConstraintTest},
 * and the schema must be migrated first — these tests switch Flyway off:
 *
 * <pre>
 * docker run --rm -d --name acct -p 55433:5432 -e POSTGRES_PASSWORD=test -e POSTGRES_DB=accounting postgis/postgis:17-3.5
 * # create schema accounting; ALTER DATABASE accounting SET search_path TO accounting, public;
 * # apply accounting V40-V52 (Flyway, with the service's own settings), then:
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
@EnabledIfSystemProperty(named = "delivery.test.postgres", matches = "true")
@DisplayName("a shop holding pickup cash, against Postgres")
class MerchantCashConstraintTest {

    @Autowired
    private CashFloatRepository floats;

    @Autowired
    private EntityManager em;

    @Test
    void a_shops_collection_and_its_payment_to_the_platform_are_kept_and_read_back() {
        String shop = "merchant-" + UUID.randomUUID();
        CashFloatEntry collected = floats.saveAndFlush(CashFloatEntry.collected(
                shop, CashFloatEntry.HolderKind.MERCHANT, UUID.randomUUID(),
                new BigDecimal("40.00"), "USD"));
        em.clear();

        // Through the Back Office's list, which projects the kind: the shop is on it as a shop.
        assertThat(floats.outstandingByHolder())
                .filteredOn(row -> row.getHolderRef().equals(shop))
                .singleElement()
                .satisfies(row -> {
                    assertThat(row.getHolderKind()).isEqualTo(CashFloatEntry.HolderKind.MERCHANT);
                    assertThat(row.getAmount()).isEqualByComparingTo("40.00");
                });

        // Paid in as any holder pays, which clears the collection.
        CashFloatEntry paid = floats.saveAndFlush(CashFloatEntry.remitted(
                shop, CashFloatEntry.HolderKind.MERCHANT, new BigDecimal("40.00"), "USD",
                new CashFloatEntry.Recorded("op-1", CashFloatEntry.Method.CASH, "till count",
                        "key-" + UUID.randomUUID())));
        floats.outstandingFor(shop).forEach(row -> row.clearedBy(paid.getId()));
        floats.flush();
        em.clear();

        assertThat(floats.outstandingTotalFor(shop)).isEqualByComparingTo("0");
        assertThat(floats.findById(collected.getId())).get()
                .extracting(CashFloatEntry::getClearedBy).isEqualTo(paid.getId());
    }

    @Test
    void a_shops_cash_is_never_a_delivery_companys() {
        assertThatThrownBy(() -> em.createNativeQuery("""
                        INSERT INTO cash_float (id, holder_ref, holder_kind, order_id, amount,
                                                currency, entry_kind, carrier_ref)
                        VALUES (gen_random_uuid(), 'merchant-a', 'MERCHANT', gen_random_uuid(),
                                40.00, 'USD', 'COLLECTED', 'company-a')
                        """).executeUpdate())
                .isInstanceOf(PersistenceException.class);
    }

    @Test
    void a_holder_nobody_defined_is_refused() {
        // The customer: exactly who the old fallback charged a pickup's cash to.
        assertThatThrownBy(() -> em.createNativeQuery("""
                        INSERT INTO cash_float (id, holder_ref, holder_kind, order_id, amount,
                                                currency, entry_kind)
                        VALUES (gen_random_uuid(), 'customer-a', 'CUSTOMER', gen_random_uuid(),
                                40.00, 'USD', 'COLLECTED')
                        """).executeUpdate())
                .isInstanceOf(PersistenceException.class);
    }

    @Test
    void the_checks_before_v52_keep_every_value_they_were_given() {
        assertThat(definitionOf("chk_float_holder")).contains("'RIDER'", "'PROVIDER'", "'MERCHANT'");
        assertThat(definitionOf("chk_float_kind"))
                .contains("'COLLECTED'", "'REMITTED'", "'TRANSFERRED'", "'WRITTEN_OFF'");
        assertThat(definitionOf("chk_float_method"))
                .contains("'CASH'", "'BANK_DEPOSIT'", "'WALLET'", "'PAYROLL_DEDUCTION'");
        assertThat(definitionOf("chk_txn_leg")).contains("'CUSTOMER_DEBIT'", "'CASH_COLLECTED'",
                "'MERCHANT_CREDIT'", "'GIFT_WRAP_CREDIT'", "'RIDER_CREDIT'", "'PROVIDER_CREDIT'",
                "'PLATFORM_COMMISSION'", "'PLATFORM_SUBSIDY'", "'CASH_REMITTANCE'",
                "'CUSTOMER_REFUND'");
        for (String kept : List.of("chk_float_custody", "chk_float_transfer_carrier",
                "chk_float_provider_carrier", "chk_float_payroll_method",
                "chk_float_merchant_carrier")) {
            assertThat(definitionOf(kept)).as(kept).isNotNull();
        }
    }

    /** The CHECK as Postgres holds it, or null when there is none by that name. */
    private String definitionOf(String name) {
        List<?> rows = em.createNativeQuery("""
                        SELECT pg_get_constraintdef(c.oid)
                          FROM pg_constraint c
                          JOIN pg_namespace n ON n.oid = c.connamespace
                         WHERE n.nspname = 'accounting' AND c.conname = ?1
                        """)
                .setParameter(1, name)
                .getResultList();
        return rows.isEmpty() ? null : (String) rows.get(0);
    }
}
