package com.delivery.accounting.domain;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;

/**
 * What V52 must say, pinned by its text — and what it must leave alone.
 *
 * <p>V52 re-creates a CHECK, and re-creating one is exactly how a value gets lost: the drop takes
 * every value with it and the add brings back only the ones somebody remembered. So, as
 * {@link CarrierCustodyMigrationTest} pins V50, this reads every accounting migration in the order
 * Flyway runs them and asks what is in force once they have all run. No build machine can run a
 * migration and Hibernate's {@code validate} never reads a CHECK, so without this a lost
 * {@code PAYROLL_DEDUCTION} would compile, pass every mocked test and refuse the first pay run at
 * deploy. {@link MerchantCashConstraintTest} proves the same against Postgres when one is there.
 */
@DisplayName("the merchant cash holder migration")
class MerchantCashMigrationTest {

    private static final Pattern VERSION = Pattern.compile("^V(\\d+(?:_\\d+)*)__.+\\.sql$");

    /** Each migration's statements, comments out and whitespace collapsed, in Flyway's order. */
    private static List<List<String>> migrations;

    private static List<String> v52;

    @BeforeAll
    static void read() throws IOException {
        Resource[] files = new PathMatchingResourcePatternResolver()
                .getResources("classpath*:db/migration/accounting/V*__*.sql");
        List<Resource> ordered = new ArrayList<>(Arrays.asList(files));
        ordered.sort(Comparator.comparing(MerchantCashMigrationTest::version,
                MerchantCashMigrationTest::compareVersions));

        migrations = new ArrayList<>();
        for (Resource file : ordered) {
            List<String> statements = statementsOf(file);
            migrations.add(statements);
            if (file.getFilename().startsWith("V52__")) {
                v52 = statements;
            }
        }
        assertThat(v52).as("V52 on the classpath").isNotNull();
        // The last migration is V52 today; a later one is read too, which is the point.
        assertThat(ordered).extracting(Resource::getFilename).contains(
                "V49_1__gift_wrap_credit_leg.sql", "V50__carrier_cash_custody.sql",
                "V51__carrier_rider_payroll.sql", "V52__merchant_cash_holder.sql");
    }

    private static List<String> statementsOf(Resource file) throws IOException {
        try (InputStream in = file.getInputStream()) {
            String sql = new String(in.readAllBytes(), StandardCharsets.UTF_8);
            return Arrays.stream(sql.replaceAll("--[^\\n]*", " ").split(";"))
                    .map(statement -> statement.replaceAll("\\s+", " ").trim())
                    .filter(statement -> !statement.isEmpty())
                    .toList();
        }
    }

    private static int[] version(Resource file) {
        Matcher matcher = VERSION.matcher(file.getFilename());
        assertThat(matcher.matches()).as(file.getFilename()).isTrue();
        return Arrays.stream(matcher.group(1).split("_")).mapToInt(Integer::parseInt).toArray();
    }

    private static int compareVersions(int[] a, int[] b) {
        for (int i = 0; i < Math.max(a.length, b.length); i++) {
            int left = i < a.length ? a[i] : 0;
            int right = i < b.length ? b[i] : 0;
            if (left != right) {
                return Integer.compare(left, right);
            }
        }
        return 0;
    }

    /**
     * The clause that defines {@code name} as Postgres holds it once every migration has run, or null
     * if the last thing any migration did to it was drop it.
     */
    private static String inForce(String name) {
        String clause = null;
        for (List<String> statements : migrations) {
            for (String statement : statements) {
                if (statement.contains("DROP CONSTRAINT " + name)) {
                    clause = null;
                }
                int at = statement.indexOf("CONSTRAINT " + name + " ");
                if (at >= 0 && !statement.contains("DROP CONSTRAINT " + name)) {
                    // Up to the next constraint, so an inline one inside CREATE TABLE reads alone.
                    int next = statement.indexOf("CONSTRAINT ", at + 1);
                    clause = statement.substring(at, next < 0 ? statement.length() : next);
                }
            }
        }
        return clause;
    }

    private static <E extends Enum<E>> String[] quoted(Class<E> values) {
        return Arrays.stream(values.getEnumConstants())
                .map(value -> "'" + value.name() + "'")
                .toArray(String[]::new);
    }

    @Test
    @DisplayName("re-creates only the holder check, keeping riders and companies beside shops")
    void onlyTheHolderCheckIsRecreated() {
        assertThat(v52)
                .filteredOn(statement -> statement.contains("DROP CONSTRAINT"))
                .singleElement()
                .satisfies(drop -> assertThat(drop).endsWith("DROP CONSTRAINT chk_float_holder"));
        assertThat(v52)
                .filteredOn(statement -> statement.contains("ADD CONSTRAINT chk_float_holder "))
                .singleElement()
                .satisfies(check -> assertThat(check)
                        .contains("'RIDER'", "'PROVIDER'", "'MERCHANT'"));
    }

    /** A pickup's notes are the platform's; no company may be made answerable for them. */
    @Test
    @DisplayName("refuses a shop's row that names a delivery company")
    void aShopRowNamesNoCompany() {
        assertThat(inForce("chk_float_merchant_carrier"))
                .contains("holder_kind <> 'MERCHANT' OR carrier_ref IS NULL");
    }

    @Test
    @DisplayName("keeps every value V49_1, V50 and V51 wrote into the checks they re-created")
    void earlierValuesSurvive() {
        assertThat(inForce("chk_txn_leg")).contains("'GIFT_WRAP_CREDIT'", "'PROVIDER_CREDIT'",
                "'PLATFORM_SUBSIDY'", "'CASH_COLLECTED'", "'CASH_REMITTANCE'");
        assertThat(inForce("chk_float_kind")).contains("'TRANSFERRED'", "'WRITTEN_OFF'");
        assertThat(inForce("chk_float_method")).contains("'CASH'", "'BANK_DEPOSIT'", "'WALLET'",
                "'PAYROLL_DEDUCTION'");
        for (String check : List.of("chk_float_custody", "chk_float_transfer_carrier",
                "chk_float_provider_carrier", "chk_float_payroll_method",
                "chk_txn_counterparty_kind", "chk_txn_counterparty_paired")) {
            assertThat(inForce(check)).as(check + " still in force").isNotNull();
        }
    }

    /**
     * The other half of the same guarantee: an enum value the entity can write and its CHECK does
     * not allow is a settlement that fails at commit. {@code ddl-auto: validate} compares columns,
     * never CHECK values, so nothing else would notice.
     */
    @Test
    @DisplayName("allows every value the entities can write")
    void checksAgreeWithTheEntities() {
        assertThat(inForce("chk_float_holder")).contains(quoted(CashFloatEntry.HolderKind.class));
        assertThat(inForce("chk_float_kind")).contains(quoted(CashFloatEntry.Kind.class));
        assertThat(inForce("chk_float_method")).contains(quoted(CashFloatEntry.Method.class));
        assertThat(inForce("chk_txn_leg")).contains(quoted(AccountingTransaction.Leg.class));
        assertThat(inForce("chk_txn_counterparty_kind")).contains(quoted(CounterpartyKind.class));
    }
}
