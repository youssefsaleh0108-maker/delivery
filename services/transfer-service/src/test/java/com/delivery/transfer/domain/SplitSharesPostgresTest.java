package com.delivery.transfer.domain;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import javax.sql.DataSource;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.TestPropertySource;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import jakarta.persistence.EntityManager;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * RECON-01's schema half, against a real Postgres: V3 lets a share be COMMITTED and simulated,
 * the entities still match the tables (Flyway from empty, then Hibernate {@code validate}), and the
 * relabelling of history changes labels only — every row that was there is still there.
 *
 * <p>Self-migrating, so it needs only an empty database, and <strong>skipped unless one is
 * there</strong>:
 *
 * <pre>
 * docker run --rm -d --name transfer-pg -p 55433:5432 -e POSTGRES_PASSWORD=postgres postgis/postgis:17-3.5
 * mvn -o -pl services/transfer-service -am test -Dtest=SplitSharesPostgresTest \
 *     -Dsurefire.failIfNoSpecifiedTests=false -Ddelivery.test.postgres=true \
 *     -Ddelivery.test.postgres.url=jdbc:postgresql://localhost:55433/postgres
 * </pre>
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@TestPropertySource(properties = {
        "spring.datasource.url=${delivery.test.postgres.url:jdbc:postgresql://localhost:55433/postgres}",
        "spring.datasource.username=${delivery.test.postgres.user:postgres}",
        "spring.datasource.password=${delivery.test.postgres.password:postgres}",
        "spring.flyway.enabled=true",
        "spring.jpa.hibernate.ddl-auto=validate",
        "spring.cloud.config.enabled=false"
})
@EnabledIfSystemProperty(named = "delivery.test.postgres", matches = "true")
@DisplayName("RECON-01: split shares against Postgres (V3)")
class SplitSharesPostgresTest {

    /** A schema of its own, so the history check can stop at V2 whatever the main one holds. */
    private static final String HISTORY = "transfer_v3_history";

    @Autowired
    private SplitPlanRepository plans;

    @Autowired
    private EntityManager em;

    @Autowired
    private DataSource dataSource;

    @Test
    @DisplayName("a committed host slice and a simulated wallet share are stored and read back")
    void committedAndSimulatedSharesRoundTrip() {
        SplitPlan plan = new SplitPlan("host-sub", "host", "Host Name", "Recon",
                SplitPlan.Mode.EVEN, new BigDecimal("19.50"), new BigDecimal("90000"),
                Instant.now().plusSeconds(900));
        SplitShare host = new SplitShare("host", "Host Name", new BigDecimal("14.50"), null);
        host.commitWithOrder();
        plan.addShare(host);
        SplitShare friend = new SplitShare("friend", "Friend", new BigDecimal("5.00"), 1);
        friend.commitSimulated(SplitShare.Method.WHISH);
        plan.addShare(friend);
        plans.saveAndFlush(plan);
        em.clear();

        SplitPlan read = plans.findById(plan.getId()).orElseThrow();

        assertThat(read.getShares()).allMatch(s -> s.getStatus() == SplitShare.Status.COMMITTED);
        assertThat(read.getShares()).allMatch(s -> s.getPaidAt() == null);
        assertThat(read.getShares())
                .filteredOn(SplitShare::isSimulated)
                .extracting(SplitShare::getPayeeUsername)
                .containsExactly("friend");
    }

    /**
     * V2's rows as the deep test left them — every answered share PAID, nothing ever carried —
     * migrated to V3: the promises become COMMITTED, the wallet one is marked simulated, and the
     * shares nobody answered, declined or covered keep exactly what they had.
     */
    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    @DisplayName("V3 relabels what was promised as PAID, and removes nothing")
    void v3RelabelsHistoryAndRemovesNothing() throws SQLException {
        exec("DROP SCHEMA IF EXISTS " + HISTORY + " CASCADE");
        try {
            flyway().target("2").load().migrate();
            UUID plan = UUID.randomUUID();
            exec("INSERT INTO " + HISTORY + ".split_plans (id, host_ref, host_username, host_name,"
                    + " order_id, mode, status, total_usd, rate_used, expires_at, created_at,"
                    + " updated_at) VALUES ('" + plan + "', 'host-sub', 'host', 'Host Name',"
                    + " gen_random_uuid(), 'EVEN', 'PLACED', 34.50, 90000, now(), now(), now())");
            share(plan, "'host'", "PAID", "'HOST_ORDER'", "14.50");
            share(plan, "NULL", "PAID", "'CASH_AT_DOOR'", "5.00");
            share(plan, "'wallet'", "PAID", "'WHISH'", "5.00");
            share(plan, "'silent'", "PENDING", "NULL", "3.00");
            share(plan, "'declined'", "DECLINED", "NULL", "3.00");
            share(plan, "'flake'", "COVERED", "'HOST_ORDER'", "4.00");

            flyway().load().migrate();

            Map<String, String> after = new LinkedHashMap<>();
            try (Connection c = dataSource.getConnection(); Statement s = c.createStatement();
                 ResultSet rows = s.executeQuery("SELECT coalesce(payee_username, 'guest'), status,"
                         + " simulated, amount_usd FROM " + HISTORY + ".split_shares"
                         + " ORDER BY payee_username NULLS FIRST")) {
                while (rows.next()) {
                    after.put(rows.getString(1), rows.getString(2) + (rows.getBoolean(3)
                            ? " simulated " : " ") + rows.getBigDecimal(4));
                }
            }
            assertThat(after).containsExactly(
                    Map.entry("guest", "COMMITTED 5.00"),
                    Map.entry("declined", "DECLINED 3.00"),
                    Map.entry("flake", "COVERED 4.00"),
                    Map.entry("host", "COMMITTED 14.50"),
                    Map.entry("silent", "PENDING 3.00"),
                    Map.entry("wallet", "COMMITTED simulated 5.00"));
        } finally {
            exec("DROP SCHEMA IF EXISTS " + HISTORY + " CASCADE");
        }
    }

    private org.flywaydb.core.api.configuration.FluentConfiguration flyway() {
        return Flyway.configure()
                .dataSource(dataSource)
                .schemas(HISTORY)
                .defaultSchema(HISTORY)
                .locations("classpath:db/migration/transfer");
    }

    private void share(UUID plan, String username, String status, String method, String amount)
            throws SQLException {
        exec("INSERT INTO " + HISTORY + ".split_shares (id, plan_id, payee_username, payee_name,"
                + " amount_usd, status, method, paid_at) VALUES (gen_random_uuid(), '" + plan + "', "
                + username + ", 'Name', " + amount + ", '" + status + "', " + method + ", "
                + ("PAID".equals(status) ? "now()" : "NULL") + ")");
    }

    private void exec(String sql) throws SQLException {
        try (Connection c = dataSource.getConnection(); Statement s = c.createStatement()) {
            s.execute(sql);
        }
    }
}
