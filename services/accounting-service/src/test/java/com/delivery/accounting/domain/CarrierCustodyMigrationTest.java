package com.delivery.accounting.domain;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * What V50 must say, pinned by its text.
 *
 * <p>No test on a build machine can run a migration, and none of the database-backed ones touches
 * this one's backfill or checks. So, as {@link RepositoryQueriesParseTest} pins the one predicate a
 * query must not lose, this pins the two clauses V50 must not: each is the difference between a
 * ledger that is right and one that reads plausibly and is wrong, and deleting either would fail no
 * other test.
 */
@DisplayName("the carrier custody migration")
class CarrierCustodyMigrationTest {

    private static List<String> statements;

    @BeforeAll
    static void read() throws IOException {
        try (InputStream in = CarrierCustodyMigrationTest.class
                .getResourceAsStream("/db/migration/accounting/V50__carrier_cash_custody.sql")) {
            assertThat(in).as("V50 on the classpath").isNotNull();
            String sql = new String(in.readAllBytes(), StandardCharsets.UTF_8);
            // Comments out and whitespace collapsed, one entry per statement, so the assertions read
            // what Postgres will run and not what a comment says it runs.
            statements = Arrays.stream(sql.replaceAll("--[^\\n]*", " ").split(";"))
                    .map(statement -> statement.replaceAll("\\s+", " ").trim())
                    .filter(statement -> !statement.isEmpty())
                    .toList();
        }
    }

    /**
     * Cash a company's rider banked with the platform before V50 was the platform's. Stamping the
     * company on it would put it on the rider's past statements as owed to the company, beside the
     * "Cash banked" line that paid it — and on the company's past days as collected and never handed
     * over.
     */
    @Test
    @DisplayName("stamps a company only on cash nobody has cleared, from both sources")
    void theBackfillLeavesBankedCashAlone() {
        List<String> backfills = statements.stream()
                .filter(statement -> statement.startsWith("UPDATE cash_float"))
                .toList();

        assertThat(backfills).hasSize(2);
        assertThat(backfills)
                .allSatisfy(update -> assertThat(update).contains("AND f.cleared_by IS NULL"));
    }

    /** A CHECK passes on NULL, so "carrier_ref = holder_ref" alone admits a company row naming none. */
    @Test
    @DisplayName("refuses a company's row that names no company")
    void aCompanyRowNamesItsCompany() {
        assertThat(statements)
                .filteredOn(statement -> statement.contains("chk_float_provider_carrier"))
                .singleElement()
                .satisfies(check -> assertThat(check)
                        .contains("carrier_ref IS NOT NULL AND carrier_ref = holder_ref"));
    }
}
